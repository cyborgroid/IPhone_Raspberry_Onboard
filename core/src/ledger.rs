//! Traffic-to-token ledger (architecture spec section 4).
//!
//! This is a local usage counter persisted on this device. It is not connected
//! to any blockchain or exchange and the tokens have no monetary value.

use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::Path;

const BYTES_PER_MIB: f64 = 1_048_576.0;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Ledger {
    /// The source of truth. Tokens are derived, so the rate can change without
    /// rewriting history and rounding errors never accumulate.
    pub total_rx_bytes: u64,
    /// Last kernel counter seen. Not persisted: the counter restarts on reboot,
    /// and traffic while the daemon was down is deliberately not credited.
    #[serde(skip)]
    last_counter: Option<u64>,
}

impl Ledger {
    /// Feed the current `rx_bytes` counter and return the bytes newly credited.
    pub fn observe(&mut self, counter: u64) -> u64 {
        let credited = match self.last_counter {
            Some(last) if counter > last => counter - last,
            // First sample is only a baseline; a lower value means the counter
            // reset because the interface was recreated.
            _ => 0,
        };
        self.last_counter = Some(counter);
        self.total_rx_bytes = self.total_rx_bytes.saturating_add(credited);
        credited
    }

    pub fn tokens(&self, tokens_per_mib: f64) -> f64 {
        self.total_rx_bytes as f64 / BYTES_PER_MIB * tokens_per_mib
    }

    /// A corrupt file is an error rather than an empty ledger, so the caller
    /// cannot overwrite a recoverable balance with zero.
    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read_to_string(path) {
            Ok(text) => serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display())),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(format!("{}: {e}", path.display())),
        }
    }

    /// Write-then-rename, so a power cut (this is a battery device) leaves
    /// either the old or the new file, never a torn one.
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        let tmp = path.with_extension("tmp");
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(serde_json::to_string(self)?.as_bytes())?;
        file.sync_all()?;
        std::fs::rename(&tmp, path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_sample_is_baseline_only() {
        let mut l = Ledger::default();
        assert_eq!(l.observe(5_000_000), 0);
        assert_eq!(l.total_rx_bytes, 0);
    }

    #[test]
    fn spec_rate_is_a_hundredth_of_a_token_per_mib() {
        let mut l = Ledger::default();
        l.observe(0);
        l.observe(1_048_576);
        assert!((l.tokens(0.01) - 0.01).abs() < 1e-12);
    }

    #[test]
    fn counter_reset_credits_nothing_then_resumes() {
        let mut l = Ledger::default();
        l.observe(1000);
        l.observe(1500);
        assert_eq!(l.observe(10), 0);
        assert_eq!(l.observe(110), 100);
        assert_eq!(l.total_rx_bytes, 600);
    }

    #[test]
    fn balance_survives_save_and_load_but_baseline_does_not() {
        let dir = std::env::temp_dir().join(format!("cyb-ledger-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ledger.json");
        let mut l = Ledger::default();
        l.observe(0);
        l.observe(4096);
        l.save(&path).unwrap();
        let mut back = Ledger::load(&path).unwrap();
        assert_eq!(back.total_rx_bytes, 4096);
        assert_eq!(back.observe(999_999), 0);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn corrupt_file_is_an_error_not_a_zero_balance() {
        let dir = std::env::temp_dir().join(format!("cyb-ledger-bad-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ledger.json");
        std::fs::write(&path, "{\"total_rx_").unwrap();
        assert!(Ledger::load(&path).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
