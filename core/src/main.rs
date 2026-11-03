//! cyborgroid-core: the backend half of the Rust/Avalonia split in the
//! architecture spec. The UI and session scripts talk to it over a Unix socket
//! using one JSON object per line.

mod config;
mod ledger;
mod system;
mod wifi;

use config::Config;
use ledger::Ledger;
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use system::{Battery, Mode, Vpn};
use wifi::SpatialReport;

const DEFAULT_CONFIG: &str = "/etc/cyborgroid/core.toml";

#[derive(Serialize)]
struct Status {
    mode: Mode,
    mode_forced: bool,
    tokens: f64,
    total_rx_bytes: u64,
    rx_error: Option<String>,
    battery: Option<Battery>,
    vpn: Vpn,
    scan_error: Option<String>,
    spatial: SpatialReport,
}

struct State {
    ledger: Ledger,
    rx_error: Option<String>,
    detected_mode: Mode,
    forced_mode: Option<Mode>,
    battery: Option<Battery>,
    vpn: Vpn,
    scan_error: Option<String>,
    spatial: SpatialReport,
}

#[derive(Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
enum Request {
    Status,
    Mode,
    /// `mode` absent means back to automatic detection.
    SetMode { mode: Option<Mode> },
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut args: Vec<&str> = args.iter().map(String::as_str).collect();
    let mut config_path = PathBuf::from(DEFAULT_CONFIG);
    if let Some(i) = args.iter().position(|a| *a == "--config") {
        let Some(path) = args.get(i + 1) else { die("--config needs a path") };
        config_path = PathBuf::from(path);
        args.drain(i..=i + 1);
    }
    let config = Config::load(&config_path).unwrap_or_else(|e| die(&e));
    match args.as_slice() {
        [] | ["daemon"] => daemon(config),
        ["query", "status"] => query(&config, r#"{"cmd":"status"}"#),
        ["query", "mode"] => query(&config, r#"{"cmd":"mode"}"#),
        ["set-mode", m @ ("mobile" | "desktop")] => {
            query(&config, &format!(r#"{{"cmd":"set_mode","mode":"{m}"}}"#))
        }
        ["set-mode", "auto"] => query(&config, r#"{"cmd":"set_mode"}"#),
        _ => die("usage: cyborgroid-core [--config FILE] [daemon | query status|mode | set-mode mobile|desktop|auto]"),
    }
}

fn die(msg: &str) -> ! {
    eprintln!("cyborgroid-core: {msg}");
    std::process::exit(1);
}

fn query(config: &Config, request: &str) {
    let run = || -> std::io::Result<String> {
        let mut stream = UnixStream::connect(&config.socket_path)?;
        writeln!(stream, "{request}")?;
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line)?;
        Ok(line)
    };
    match run() {
        // The mode reply is a bare JSON string; scripts want it unquoted.
        Ok(line) => println!("{}", line.trim().trim_matches('"')),
        Err(e) => die(&format!("{}: {e}", config.socket_path.display())),
    }
}

fn daemon(config: Config) {
    let ledger_path = config.state_dir.join("ledger.json");
    std::fs::create_dir_all(&config.state_dir)
        .unwrap_or_else(|e| die(&format!("{}: {e}", config.state_dir.display())));
    let ledger = Ledger::load(&ledger_path).unwrap_or_else(|e| die(&e));

    let terminate = Arc::new(AtomicBool::new(false));
    for sig in signal_hook::consts::TERM_SIGNALS {
        signal_hook::flag::register(*sig, terminate.clone()).unwrap_or_else(|e| die(&e.to_string()));
    }

    let state = Arc::new(Mutex::new(State {
        ledger,
        rx_error: None,
        detected_mode: system::detect_mode(&config.sys_root),
        forced_mode: None,
        battery: None,
        vpn: system::vpn(&config.sys_root, &config.wg_interface, &config.killswitch_marker),
        scan_error: None,
        spatial: SpatialReport::default(),
    }));

    let listener = bind_socket(&config.socket_path);
    {
        let (state, config) = (state.clone(), config.clone());
        thread::spawn(move || serve(listener, state, config));
    }
    {
        let (state, config) = (state.clone(), config.clone());
        thread::spawn(move || scan_loop(state, config));
    }

    println!(
        "cyborgroid-core: engine started on {} (socket {})",
        config.interface,
        config.socket_path.display()
    );
    tick_loop(state, &config, &ledger_path, &terminate);
}

fn bind_socket(path: &Path) -> UnixListener {
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    // A stale socket from an unclean exit would make bind fail.
    let _ = std::fs::remove_file(path);
    UnixListener::bind(path).unwrap_or_else(|e| die(&format!("{}: {e}", path.display())))
}

fn tick_loop(state: Arc<Mutex<State>>, config: &Config, ledger_path: &Path, terminate: &AtomicBool) {
    let save_every = Duration::from_secs(config.ledger_save_secs);
    let tick = Duration::from_secs(config.tick_secs);
    let mut last_save = Instant::now();
    let mut dirty = false;
    let mut next_tick = Instant::now();
    while !terminate.load(Ordering::Relaxed) {
        // Short sleeps so SIGTERM saves the ledger promptly at shutdown.
        thread::sleep(Duration::from_millis(200));
        if Instant::now() < next_tick {
            continue;
        }
        next_tick = Instant::now() + tick;

        let rx = system::rx_bytes(&config.sys_root, &config.interface);
        // Slow external commands run outside the lock so IPC never stalls on them.
        let mode = system::detect_mode(&config.sys_root);
        let battery = system::battery(&config.sys_root);
        let vpn = system::vpn(&config.sys_root, &config.wg_interface, &config.killswitch_marker);

        let mut s = state.lock().unwrap();
        match rx {
            Ok(counter) => {
                dirty |= s.ledger.observe(counter) > 0;
                s.rx_error = None;
            }
            Err(e) => s.rx_error = Some(e),
        }
        s.detected_mode = mode;
        s.battery = battery;
        s.vpn = vpn;

        if dirty && last_save.elapsed() >= save_every {
            match s.ledger.save(ledger_path) {
                Ok(()) => {
                    dirty = false;
                    last_save = Instant::now();
                }
                Err(e) => eprintln!("cyborgroid-core: saving ledger: {e}"),
            }
        }
    }
    if let Err(e) = state.lock().unwrap().ledger.save(ledger_path) {
        eprintln!("cyborgroid-core: saving ledger at shutdown: {e}");
    }
}

fn scan_loop(state: Arc<Mutex<State>>, config: Config) {
    loop {
        let result = wifi::scan(&config.interface);
        let mut s = state.lock().unwrap();
        match result {
            Ok(aps) => {
                s.spatial = wifi::analyze(aps, previous_scan(&s.spatial));
                s.scan_error = None;
            }
            Err(e) => s.scan_error = Some(e),
        }
        drop(s);
        thread::sleep(Duration::from_secs(config.scan_secs));
    }
}

/// `ap_count` 0 with no `similarity` is the initial, never-scanned report.
fn previous_scan(report: &SpatialReport) -> Option<&[wifi::AccessPoint]> {
    (report.ap_count > 0 || report.similarity.is_some()).then_some(&report.access_points[..])
}

fn serve(listener: UnixListener, state: Arc<Mutex<State>>, config: Config) {
    for stream in listener.incoming().flatten() {
        let (state, config) = (state.clone(), config.clone());
        thread::spawn(move || {
            if let Err(e) = handle_client(stream, &state, &config) {
                eprintln!("cyborgroid-core: client: {e}");
            }
        });
    }
}

fn handle_client(stream: UnixStream, state: &Mutex<State>, config: &Config) -> std::io::Result<()> {
    let mut writer = stream.try_clone()?;
    for line in BufReader::new(stream).lines() {
        let reply = respond(&line?, state, config);
        writeln!(writer, "{reply}")?;
    }
    Ok(())
}

fn respond(line: &str, state: &Mutex<State>, config: &Config) -> String {
    let request: Request = match serde_json::from_str(line) {
        Ok(r) => r,
        Err(e) => return serde_json::json!({ "error": e.to_string() }).to_string(),
    };
    let mut s = state.lock().unwrap();
    let mode = s.forced_mode.unwrap_or(s.detected_mode);
    let result = match request {
        Request::Mode => serde_json::to_string(&mode),
        Request::SetMode { mode } => {
            s.forced_mode = mode;
            serde_json::to_string(&mode.unwrap_or(s.detected_mode))
        }
        Request::Status => serde_json::to_string(&Status {
            mode,
            mode_forced: s.forced_mode.is_some(),
            tokens: s.ledger.tokens(config.tokens_per_mib),
            total_rx_bytes: s.ledger.total_rx_bytes,
            rx_error: s.rx_error.clone(),
            battery: s.battery.clone(),
            vpn: s.vpn.clone(),
            scan_error: s.scan_error.clone(),
            spatial: s.spatial.clone(),
        }),
    };
    result.unwrap_or_else(|e| serde_json::json!({ "error": e.to_string() }).to_string())
}
