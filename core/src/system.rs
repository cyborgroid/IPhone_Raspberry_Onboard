//! Device state read from sysfs and procfs: form-factor mode, battery, VPN.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Mobile,
    Desktop,
}

#[derive(Debug, Clone, Serialize)]
pub struct Battery {
    pub percent: u8,
    pub charging: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct Vpn {
    pub interface_up: bool,
    /// Seconds since the last handshake. None if there has never been one or
    /// `wg` could not be queried.
    pub handshake_age_secs: Option<u64>,
    pub connected: bool,
    pub killswitch: bool,
}

/// WireGuard re-handshakes every 2 minutes on an active tunnel; 180 s is the
/// point at which it gives up on the current session.
const HANDSHAKE_FRESH_SECS: u64 = 180;

fn read_trim(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_owned())
}

pub fn rx_bytes(sys_root: &Path, interface: &str) -> Result<u64, String> {
    let path = sys_root.join("class/net").join(interface).join("statistics/rx_bytes");
    let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    text.trim().parse().map_err(|e| format!("{}: {e}", path.display()))
}

pub fn external_display_connected(sys_root: &Path) -> bool {
    let Ok(entries) = fs::read_dir(sys_root.join("class/drm")) else { return false };
    entries.flatten().any(|e| {
        e.file_name().to_string_lossy().contains("-HDMI-")
            && read_trim(&e.path().join("status")).as_deref() == Some("connected")
    })
}

/// The touchscreen runs Ubuntu Touch; a connected monitor means the full Ubuntu
/// desktop. A DSI panel has a different connector name, so it never matches.
pub fn detect_mode(sys_root: &Path) -> Mode {
    if external_display_connected(sys_root) {
        Mode::Desktop
    } else {
        Mode::Mobile
    }
}

/// None when there is no fuel gauge, which is the case on a bare Pi 5. The UI
/// must then say so rather than show an invented percentage.
pub fn battery(sys_root: &Path) -> Option<Battery> {
    let entries = fs::read_dir(sys_root.join("class/power_supply")).ok()?;
    entries.flatten().find_map(|e| {
        let p = e.path();
        if read_trim(&p.join("type")).as_deref() != Some("Battery") {
            return None;
        }
        let percent = read_trim(&p.join("capacity"))?.parse::<u8>().ok()?.min(100);
        let status = read_trim(&p.join("status")).unwrap_or_default();
        Some(Battery { percent, charging: status == "Charging" || status == "Full" })
    })
}

/// Parses `wg show <if> latest-handshakes`: `<pubkey>\t<unix-seconds>` per peer,
/// with 0 meaning never. Returns the newest handshake's age.
pub fn parse_handshake_age(output: &str, now_secs: u64) -> Option<u64> {
    output
        .lines()
        .filter_map(|l| l.split_whitespace().nth(1)?.parse::<u64>().ok())
        .filter(|&t| t > 0)
        .max()
        .map(|t| now_secs.saturating_sub(t))
}

pub fn vpn(sys_root: &Path, wg_interface: &str, killswitch_marker: &Path) -> Vpn {
    let interface_up = sys_root.join("class/net").join(wg_interface).exists();
    let handshake_age_secs = interface_up.then(|| {
        let out = Command::new("timeout")
            .args(["5", "wg", "show", wg_interface, "latest-handshakes"])
            .output()
            .ok()?;
        let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
        parse_handshake_age(&String::from_utf8_lossy(&out.stdout), now)
    }).flatten();
    Vpn {
        interface_up,
        handshake_age_secs,
        connected: handshake_age_secs.is_some_and(|a| a < HANDSHAKE_FRESH_SECS),
        killswitch: killswitch_marker.exists(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handshake_age_uses_newest_peer_and_ignores_never() {
        assert_eq!(parse_handshake_age("k1\t0\nk2\t900\nk3\t950\n", 1000), Some(50));
        assert_eq!(parse_handshake_age("k1\t0\n", 1000), None);
        assert_eq!(parse_handshake_age("", 1000), None);
    }

    fn fake_tree(name: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("cyb-sys-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn mode_follows_the_monitor_and_ignores_the_panel() {
        let root = fake_tree("mode");
        let dsi = root.join("class/drm/card1-DSI-1");
        fs::create_dir_all(&dsi).unwrap();
        fs::write(dsi.join("status"), "connected\n").unwrap();
        assert_eq!(detect_mode(&root), Mode::Mobile);

        let hdmi = root.join("class/drm/card2-HDMI-A-1");
        fs::create_dir_all(&hdmi).unwrap();
        fs::write(hdmi.join("status"), "disconnected\n").unwrap();
        assert_eq!(detect_mode(&root), Mode::Mobile);

        fs::write(hdmi.join("status"), "connected\n").unwrap();
        assert_eq!(detect_mode(&root), Mode::Desktop);
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn battery_is_absent_without_a_gauge() {
        let root = fake_tree("bat");
        assert!(battery(&root).is_none());
        let ac = root.join("class/power_supply/rpi-usb");
        fs::create_dir_all(&ac).unwrap();
        fs::write(ac.join("type"), "USB\n").unwrap();
        assert!(battery(&root).is_none());

        let bat = root.join("class/power_supply/BAT0");
        fs::create_dir_all(&bat).unwrap();
        fs::write(bat.join("type"), "Battery\n").unwrap();
        fs::write(bat.join("capacity"), "78\n").unwrap();
        fs::write(bat.join("status"), "Charging\n").unwrap();
        let b = battery(&root).unwrap();
        assert_eq!((b.percent, b.charging), (78, true));
        fs::remove_dir_all(&root).unwrap();
    }
}
