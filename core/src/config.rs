//! Daemon configuration. Every key is optional; see `os/overlay/etc/cyborgroid/core.toml`.

use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// Interface whose received bytes feed the ledger and which is scanned.
    pub interface: String,
    pub wg_interface: String,
    /// Tokens per MiB received. The architecture spec fixes this at 0.01.
    pub tokens_per_mib: f64,
    pub tick_secs: u64,
    pub scan_secs: u64,
    pub ledger_save_secs: u64,
    pub socket_path: PathBuf,
    pub state_dir: PathBuf,
    /// Written by `wireguard-killswitch.sh` while the firewall is closed.
    pub killswitch_marker: PathBuf,
    /// Overridable so dev machines can point at a fake tree.
    pub sys_root: PathBuf,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            interface: "wlan0".into(),
            wg_interface: "wg0".into(),
            tokens_per_mib: 0.01,
            tick_secs: 5,
            scan_secs: 30,
            ledger_save_secs: 60,
            socket_path: "/run/cyborgroid/core.sock".into(),
            state_dir: "/var/lib/cyborgroid".into(),
            killswitch_marker: "/run/cyborgroid-net/killswitch.active".into(),
            sys_root: "/sys".into(),
        }
    }
}

impl Config {
    /// A missing file means defaults; a malformed one is an error so that a
    /// typo cannot silently change what the daemon does.
    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read_to_string(path) {
            Ok(text) => toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display())),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(format!("{}: {e}", path.display())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_file_keeps_defaults() {
        let c: Config = toml::from_str("interface = \"wlan1\"").unwrap();
        assert_eq!(c.interface, "wlan1");
        assert_eq!(c.tokens_per_mib, 0.01);
    }

    #[test]
    fn unknown_key_is_rejected() {
        assert!(toml::from_str::<Config>("interfase = \"wlan1\"").is_err());
    }
}
