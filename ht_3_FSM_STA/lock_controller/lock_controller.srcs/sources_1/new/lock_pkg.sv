// lock_pkg.sv
// Shared package: the state_t type lives here so both lock_controller.sv
// and tb_lock_controller.sv can reference it directly by name (import),
// instead of reaching into the DUT through a hierarchical path.

package lock_pkg;
    typedef enum logic [1:0] {
        LOCKED,
        WAIT_D2,
        WAIT_D3,
        UNLOCKED
    } state_t;
endpackage