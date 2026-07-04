/// Shared ride constants used by both the client (rider) and provider
/// (driver) apps so the two stay in lockstep.
library;

/// Free waiting period, in seconds, once the driver has arrived at pickup.
///
/// During this window the rider is not charged for waiting and the driver
/// cannot cancel a no-show penalty-free; once it elapses the rider accrues
/// wait charges and the driver may cancel without penalty.
///
/// Both apps anchor their countdown to the server's `arrivedAtPickupAt`
/// timestamp, so the rider's and driver's clocks show the same remaining
/// time. Mirrors the backend `ride_driver_wait_window_secs` config.
const int kFreeWaitAtPickupSeconds = 180;
