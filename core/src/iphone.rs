//! A USB iPhone: seen in sysfs, paired through libimobiledevice (which talks to
//! usbmuxd), and used as an uplink through the kernel's `ipheth` tethering driver.

use serde::Serialize;
use std::fs;
use std::path::Path;
use std::process::Command;

const APPLE_VENDOR: &str = "05ac";
const TETHER_DRIVER: &str = "ipheth";
const TOOL_TIMEOUT_SECS: &str = "10";
/// GNU `timeout` exits with these when the command is missing or ran too long.
const EXIT_NOT_FOUND: i32 = 127;
const EXIT_TIMED_OUT: i32 = 124;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PairState {
    #[default]
    Absent,
    /// On USB, but usbmuxd has no device to talk to yet.
    NotReady,
    NotPaired,
    AwaitingTrust,
    Locked,
    Denied,
    Paired,
    ToolsMissing,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DeviceInfo {
    pub device_name: Option<String>,
    pub model: Option<String>,
    pub ios_version: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct IPhone {
    pub state: PairState,
    pub info: Option<DeviceInfo>,
    /// Present while the phone offers tethering; `tether_up` means Personal Hotspot
    /// is on and the link has carrier, not that the internet is reachable.
    pub tether_interface: Option<String>,
    pub tether_up: bool,
    pub error: Option<String>,
}

fn read_trim(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_owned())
}

pub fn on_usb(sys_root: &Path) -> bool {
    let Ok(entries) = fs::read_dir(sys_root.join("bus/usb/devices")) else { return false };
    entries.flatten().any(|e| {
        let p = e.path();
        read_trim(&p.join("idVendor")).as_deref() == Some(APPLE_VENDOR)
            && read_trim(&p.join("product")).is_some_and(|name| name.starts_with("iPhone"))
    })
}

/// Finds the tethering link by driver, because its name is derived from a MAC
/// address the phone randomizes.
pub fn tether_link(sys_root: &Path) -> Option<(String, bool)> {
    let entries = fs::read_dir(sys_root.join("class/net")).ok()?;
    entries.flatten().find_map(|e| {
        let driver = fs::read_link(e.path().join("device/driver")).ok()?;
        if driver.file_name()? != TETHER_DRIVER {
            return None;
        }
        let up = read_trim(&e.path().join("operstate")).as_deref() == Some("up");
        Some((e.file_name().to_string_lossy().into_owned(), up))
    })
}

/// Classifies `idevicepair` output. Its messages name the device's UDID, so only
/// the error code is passed on.
pub fn parse_pair_output(output: &str) -> (PairState, Option<String>) {
    let state = if output.contains("SUCCESS") {
        PairState::Paired
    } else if output.contains("passcode") {
        PairState::Locked
    } else if output.contains("denied") {
        PairState::Denied
    } else if output.contains("trust dialog") {
        PairState::AwaitingTrust
    } else if output.contains("not paired") {
        PairState::NotPaired
    } else if output.contains("No device found") {
        PairState::NotReady
    } else {
        let code = output.split("error code ").nth(1).and_then(|s| s.split_whitespace().next());
        return (PairState::Error, Some(format!("idevicepair error code {}", code.unwrap_or("unknown"))));
    };
    (state, None)
}

/// Parses the `Key: value` lines of `ideviceinfo`.
pub fn parse_device_info(output: &str) -> DeviceInfo {
    let value = |key: &str| {
        output.lines().find_map(|l| {
            let (k, v) = l.split_once(": ")?;
            (k == key).then(|| v.trim().to_owned())
        })
    };
    DeviceInfo {
        device_name: value("DeviceName"),
        model: value("ProductType"),
        ios_version: value("ProductVersion"),
    }
}

fn run_tool(tool: &str, args: &[&str]) -> Result<String, (PairState, Option<String>)> {
    let output = Command::new("timeout").arg(TOOL_TIMEOUT_SECS).arg(tool).args(args).output();
    let Ok(output) = output else { return Err((PairState::ToolsMissing, None)) };
    match output.status.code() {
        Some(EXIT_NOT_FOUND) => Err((PairState::ToolsMissing, None)),
        Some(EXIT_TIMED_OUT) => Err((PairState::Error, Some(format!("{tool} timed out")))),
        _ => {
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&output.stderr));
            Ok(text)
        }
    }
}

/// `pair` opens the trust dialog on the phone, and has to be repeated after the
/// owner accepts it to save the pairing; `validate` only reports.
pub fn poll(sys_root: &Path, pair: bool, known: Option<DeviceInfo>) -> IPhone {
    if !on_usb(sys_root) {
        return IPhone::default();
    }
    let command = if pair { "pair" } else { "validate" };
    let (state, error) = match run_tool("idevicepair", &[command]) {
        Ok(output) => parse_pair_output(&output),
        Err(result) => result,
    };
    let info = (state == PairState::Paired)
        .then(|| known.or_else(|| run_tool("ideviceinfo", &[]).ok().map(|o| parse_device_info(&o))))
        .flatten();
    let tether = tether_link(sys_root);
    IPhone {
        state,
        info,
        tether_up: tether.as_ref().is_some_and(|(_, up)| *up),
        tether_interface: tether.map(|(name, _)| name),
        error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_tree(name: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("cyb-iphone-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn pair_output_covers_each_idevicepair_message() {
        let cases = [
            ("SUCCESS: Paired with device X\n", PairState::Paired),
            ("SUCCESS: Validated pairing with device X\n", PairState::Paired),
            ("ERROR: Could not validate with device X because a passcode is set. Please enter the passcode on the device and retry.\n", PairState::Locked),
            ("ERROR: Device X is not paired with this host\n", PairState::NotPaired),
            ("ERROR: Please accept the trust dialog on the screen of device X, then attempt to pair again.\n", PairState::AwaitingTrust),
            ("ERROR: Device X said that the user denied the trust dialog.\n", PairState::Denied),
            ("No device found.\n", PairState::NotReady),
        ];
        for (output, expected) in cases {
            assert_eq!(parse_pair_output(output), (expected, None), "{output}");
        }
    }

    #[test]
    fn unknown_failure_keeps_the_code_and_drops_the_udid() {
        let (state, error) = parse_pair_output("ERROR: Device SECRETUDID returned unhandled error code -5\n");
        assert_eq!(state, PairState::Error);
        assert_eq!(error.as_deref(), Some("idevicepair error code -5"));

        let (state, error) = parse_pair_output("something else from SECRETUDID\n");
        assert_eq!(state, PairState::Error);
        assert_eq!(error.as_deref(), Some("idevicepair error code unknown"));
    }

    #[test]
    fn device_info_matches_whole_keys_only() {
        let info = parse_device_info(
            "ProductVersion: 26.1\nHumanReadableProductVersionString: 26.1 beta\nDeviceName: My: Phone\nProductType: iPhone14,5\n",
        );
        assert_eq!(info.device_name.as_deref(), Some("My: Phone"));
        assert_eq!(info.model.as_deref(), Some("iPhone14,5"));
        assert_eq!(info.ios_version.as_deref(), Some("26.1"));
        assert_eq!(parse_device_info("").model, None);
    }

    #[test]
    fn only_an_iphone_counts_as_on_usb() {
        let root = fake_tree("usb");
        assert!(!on_usb(&root));

        let keyboard = root.join("bus/usb/devices/3-1");
        fs::create_dir_all(&keyboard).unwrap();
        fs::write(keyboard.join("idVendor"), "05ac\n").unwrap();
        fs::write(keyboard.join("product"), "Apple Keyboard\n").unwrap();
        assert!(!on_usb(&root));

        let phone = root.join("bus/usb/devices/3-10");
        fs::create_dir_all(&phone).unwrap();
        fs::write(phone.join("idVendor"), "05ac\n").unwrap();
        fs::write(phone.join("product"), "iPhone\n").unwrap();
        assert!(on_usb(&root));
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn absent_phone_needs_no_tools() {
        let root = fake_tree("absent");
        let report = poll(&root, true, None);
        assert_eq!(report.state, PairState::Absent);
        assert!(report.tether_interface.is_none());
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn tether_link_is_found_by_driver_not_name() {
        let root = fake_tree("tether");
        let net = root.join("class/net");
        for (name, driver) in [("eth0", "r8169"), ("enxaabbcc", "ipheth")] {
            let device = net.join(name).join("device");
            fs::create_dir_all(&device).unwrap();
            std::os::unix::fs::symlink(format!("../../../bus/usb/drivers/{driver}"), device.join("driver")).unwrap();
            fs::write(net.join(name).join("operstate"), "down\n").unwrap();
        }
        fs::create_dir_all(net.join("lo")).unwrap();
        assert_eq!(tether_link(&root), Some(("enxaabbcc".to_owned(), false)));

        fs::write(net.join("enxaabbcc/operstate"), "up\n").unwrap();
        assert_eq!(tether_link(&root), Some(("enxaabbcc".to_owned(), true)));
        fs::remove_dir_all(&root).unwrap();
    }
}
