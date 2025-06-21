;; DeFi Yield Optimizer - Auto-Compounding Protocol for Stacks
;; Features: Strategy Vaults, Auto-Compounding, Risk Management, Performance Tracking

;; Constants
(define-constant PROTOCOL_ADMIN tx-sender)
(define-constant ERR_UNAUTHORIZED_ACCESS (err u601))
(define-constant ERR_INVALID_DEPOSIT_AMOUNT (err u602))
(define-constant ERR_INSUFFICIENT_VAULT_BALANCE (err u603))
(define-constant ERR_STRATEGY_PAUSED (err u604))
(define-constant ERR_INVALID_STRATEGY_PARAMS (err u605))
(define-constant ERR_WITHDRAWAL_COOLDOWN_ACTIVE (err u606))
(define-constant ERR_STRATEGY_NOT_FOUND (err u607))
(define-constant ERR_INVALID_PERFORMANCE_FEE (err u608))
(define-constant ERR_MAX_ALLOCATION_EXCEEDED (err u609))
(define-constant ERR_EMERGENCY_SHUTDOWN_ACTIVE (err u610))

;; Data Variables
(define-data-var total-value-locked uint u0)
(define-data-var protocol-performance-fee uint u200) ;; 2% performance fee
(define-data-var emergency-shutdown bool false)
(define-data-var auto-compound-frequency uint u144) ;; Auto-compound every 144 blocks (~24 hours)
(define-data-var strategy-counter uint u0)

;; Data Maps
(define-map investor-vault-positions
  {investor: principal, strategy-id: uint}
  {
    deposited-amount: uint,
    vault-shares: uint,
    entry-timestamp: uint,
    last-compound-block: uint,
    accumulated-rewards: uint
  }
)

(define-map yield-strategies
  uint
  {
    strategy-name: (string-ascii 64),
    manager: principal,
    target-apy: uint, ;; in basis points
    risk-level: uint, ;; 1-5 scale
    total-deposits: uint,
    total-rewards-generated: uint,
    strategy-active: bool,
    max-allocation: uint,
    performance-multiplier: uint
  }
)

(define-map strategy-performance-history
  {strategy-id: uint, epoch: uint}
  {
    period-start: uint,
    period-end: uint,
    deposits-at-start: uint,
    deposits-at-end: uint,
    rewards-generated: uint,
    actual-apy: uint
  }
)

(define-map authorized-strategy-managers principal bool)
(define-map investor-withdrawal-cooldowns
  principal
  {
    last-withdrawal: uint,
    cooldown-blocks: uint
  }
)

(define-map protocol-treasury-allocation
  (string-ascii 32)
  uint
)

;; Performance tracking
(define-data-var current-epoch uint u1)
(define-data-var epoch-duration uint u1008) ;; 1 week epochs

;; Authorization Functions
(define-private (is-protocol-admin)
  (is-eq tx-sender PROTOCOL_ADMIN)
)

(define-private (is-authorized-manager (manager principal))
  (default-to false (map-get? authorized-strategy-managers manager))
)

(define-private (can-manage-strategy (strategy-id uint))
  (match (map-get? yield-strategies strategy-id)
    strategy-data (or (is-protocol-admin) (is-eq tx-sender (get manager strategy-data)))
    false
  )
)

;; Administrative Functions
(define-public (authorize-strategy-manager (manager principal))
  (begin
    (asserts! (is-protocol-admin) ERR_UNAUTHORIZED_ACCESS)
    (ok (map-set authorized-strategy-managers manager true))
  )
)

(define-public (revoke-strategy-manager (manager principal))
  (begin
    (asserts! (is-protocol-admin) ERR_UNAUTHORIZED_ACCESS)
    (ok (map-delete authorized-strategy-managers manager))
  )
)

(define-public (update-performance-fee (new-fee uint))
  (begin
    (asserts! (is-protocol-admin) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (<= new-fee u1000) ERR_INVALID_PERFORMANCE_FEE) ;; Max 10% fee
    (ok (var-set protocol-performance-fee new-fee))
  )
)

(define-public (emergency-shutdown-protocol)
  (begin
    (asserts! (is-protocol-admin) ERR_UNAUTHORIZED_ACCESS)
    (var-set emergency-shutdown true)
    (print {event: "emergency-shutdown-activated", admin: tx-sender})
    (ok true)
  )
)

(define-public (reactivate-protocol)
  (begin
    (asserts! (is-protocol-admin) ERR_UNAUTHORIZED_ACCESS)
    (var-set emergency-shutdown false)
    (print {event: "protocol-reactivated", admin: tx-sender})
    (ok true)
  )
)

;; Strategy Management Functions
(define-public (create-yield-strategy 
  (strategy-name (string-ascii 64))
  (target-apy uint)
  (risk-level uint)
  (max-allocation uint)
  (performance-multiplier uint))
  (let (
    (strategy-id (+ (var-get strategy-counter) u1))
  )
    (asserts! (is-authorized-manager tx-sender) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN_ACTIVE)
    (asserts! (and (<= risk-level u5) (> risk-level u0)) ERR_INVALID_STRATEGY_PARAMS)
    (asserts! (<= target-apy u5000) ERR_INVALID_STRATEGY_PARAMS) ;; Max 50% APY
    (asserts! (<= performance-multiplier u300) ERR_INVALID_STRATEGY_PARAMS) ;; Max 3x multiplier
    
    ;; Create new strategy
    (map-set yield-strategies strategy-id {
      strategy-name: strategy-name,
      manager: tx-sender,
      target-apy: target-apy,
      risk-level: risk-level,
      total-deposits: u0,
      total-rewards-generated: u0,
      strategy-active: true,
      max-allocation: max-allocation,
      performance-multiplier: performance-multiplier
    })
    
    ;; Update counter
    (var-set strategy-counter strategy-id)
    
    (print {
      event: "yield-strategy-created",
      strategy-id: strategy-id,
      manager: tx-sender,
      strategy-name: strategy-name,
      target-apy: target-apy,
      risk-level: risk-level
    })
    
    (ok strategy-id)
  )
)

(define-public (toggle-strategy-status (strategy-id uint))
  (let (
    (strategy-data (unwrap! (map-get? yield-strategies strategy-id) ERR_STRATEGY_NOT_FOUND))
  )
    (asserts! (can-manage-strategy strategy-id) ERR_UNAUTHORIZED_ACCESS)
    
    (map-set yield-strategies strategy-id
      (merge strategy-data {strategy-active: (not (get strategy-active strategy-data))})
    )
    
    (print {
      event: "strategy-status-toggled",
      strategy-id: strategy-id,
      new-status: (not (get strategy-active strategy-data)),
      manager: tx-sender
    })
    
    (ok (not (get strategy-active strategy-data)))
  )
)

;; Core Investment Functions
(define-public (deposit-to-strategy (strategy-id uint) (amount uint))
  (let (
    (strategy-data (unwrap! (map-get? yield-strategies strategy-id) ERR_STRATEGY_NOT_FOUND))
    (current-position (default-to 
      {deposited-amount: u0, vault-shares: u0, entry-timestamp: block-height, 
       last-compound-block: block-height, accumulated-rewards: u0}
      (map-get? investor-vault-positions {investor: tx-sender, strategy-id: strategy-id})
    ))
    (vault-shares (calculate-vault-shares amount (get total-deposits strategy-data)))
  )
    (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN_ACTIVE)
    (asserts! (get strategy-active strategy-data) ERR_STRATEGY_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_DEPOSIT_AMOUNT)
    (asserts! (<= (+ (get total-deposits strategy-data) amount) (get max-allocation strategy-data)) ERR_MAX_ALLOCATION_EXCEEDED)
    
    ;; Update investor position
    (map-set investor-vault-positions {investor: tx-sender, strategy-id: strategy-id} {
      deposited-amount: (+ (get deposited-amount current-position) amount),
      vault-shares: (+ (get vault-shares current-position) vault-shares),
      entry-timestamp: (get entry-timestamp current-position),
      last-compound-block: block-height,
      accumulated-rewards: (get accumulated-rewards current-position)
    })
    
    ;; Update strategy totals
    (map-set yield-strategies strategy-id
      (merge strategy-data {total-deposits: (+ (get total-deposits strategy-data) amount)})
    )
    
    ;; Update protocol TVL
    (var-set total-value-locked (+ (var-get total-value-locked) amount))
    
    (print {
      event: "deposit-to-strategy",
      investor: tx-sender,
      strategy-id: strategy-id,
      amount: amount,
      vault-shares: vault-shares,
      new-total-deposits: (+ (get total-deposits strategy-data) amount)
    })
    
    (ok vault-shares)
  )
)

(define-public (withdraw-from-strategy (strategy-id uint) (shares-to-withdraw uint))
  (let (
    (strategy-data (unwrap! (map-get? yield-strategies strategy-id) ERR_STRATEGY_NOT_FOUND))
    (investor-position (unwrap! (map-get? investor-vault-positions {investor: tx-sender, strategy-id: strategy-id}) ERR_INSUFFICIENT_VAULT_BALANCE))
    (cooldown-info (default-to {last-withdrawal: u0, cooldown-blocks: u72} (map-get? investor-withdrawal-cooldowns tx-sender)))
    (withdrawal-amount (calculate-withdrawal-amount shares-to-withdraw (get vault-shares investor-position) (get deposited-amount investor-position)))
  )
    (asserts! (not (var-get emergency-shutdown)) ERR_EMERGENCY_SHUTDOWN_ACTIVE)
    (asserts! (>= (get vault-shares investor-position) shares-to-withdraw) ERR_INSUFFICIENT_VAULT_BALANCE)
    (asserts! (>= block-height (+ (get last-withdrawal cooldown-info) (get cooldown-blocks cooldown-info))) ERR_WITHDRAWAL_COOLDOWN_ACTIVE)
    
    ;; Update investor position
    (map-set investor-vault-positions {investor: tx-sender, strategy-id: strategy-id}
      (merge investor-position {
        deposited-amount: (- (get deposited-amount investor-position) withdrawal-amount),
        vault-shares: (- (get vault-shares investor-position) shares-to-withdraw)
      })
    )
    
    ;; Update strategy totals
    (map-set yield-strategies strategy-id
      (merge strategy-data {total-deposits: (- (get total-deposits strategy-data) withdrawal-amount)})
    )
    
    ;; Update withdrawal cooldown
    (map-set investor-withdrawal-cooldowns tx-sender {
      last-withdrawal: block-height,
      cooldown-blocks: u72
    })
    
    ;; Update protocol TVL
    (var-set total-value-locked (- (var-get total-value-locked) withdrawal-amount))
    
    (print {
      event: "withdraw-from-strategy",
      investor: tx-sender,
      strategy-id: strategy-id,
      shares-withdrawn: shares-to-withdraw,
      amount-withdrawn: withdrawal-amount
    })
    
    (ok withdrawal-amount)
  )
)

;; Auto-Compounding Functions
(define-public (trigger-auto-compound (strategy-id uint))
  (let (
    (strategy-data (unwrap! (map-get? yield-strategies strategy-id) ERR_STRATEGY_NOT_FOUND))
    (blocks-since-compound (- block-height (var-get auto-compound-frequency)))
    (generated-yield (calculate-strategy-yield strategy-id blocks-since-compound))
    (performance-fee (/ (* generated-yield (var-get protocol-performance-fee)) u10000))
    (net-yield (- generated-yield performance-fee))
  )
    (asserts! (get strategy-active strategy-data) ERR_STRATEGY_PAUSED)
    (asserts! (>= blocks-since-compound (var-get auto-compound-frequency)) ERR_INVALID_STRATEGY_PARAMS)
    
    ;; Update strategy with compounded yield
    (map-set yield-strategies strategy-id
      (merge strategy-data {
        total-deposits: (+ (get total-deposits strategy-data) net-yield),
        total-rewards-generated: (+ (get total-rewards-generated strategy-data) generated-yield)
      })
    )
    
    ;; Add performance fee to protocol treasury
    (map-set protocol-treasury-allocation "performance-fees" 
      (+ (default-to u0 (map-get? protocol-treasury-allocation "performance-fees")) performance-fee)
    )
    
    ;; Update protocol TVL
    (var-set total-value-locked (+ (var-get total-value-locked) net-yield))
    
    (print {
      event: "auto-compound-executed",
      strategy-id: strategy-id,
      generated-yield: generated-yield,
      performance-fee: performance-fee,
      net-yield: net-yield,
      compounder: tx-sender
    })
    
    (ok net-yield)
  )
)

(define-public (compound-investor-position (strategy-id uint))
  (let (
    (investor-position (unwrap! (map-get? investor-vault-positions {investor: tx-sender, strategy-id: strategy-id}) ERR_INSUFFICIENT_VAULT_BALANCE))
    (blocks-held (- block-height (get last-compound-block investor-position)))
    (individual-yield (calculate-individual-yield strategy-id tx-sender blocks-held))
  )
    (asserts! (> individual-yield u0) ERR_INVALID_DEPOSIT_AMOUNT)
    
    ;; Update investor position with compounded yield
    (map-set investor-vault-positions {investor: tx-sender, strategy-id: strategy-id}
      (merge investor-position {
        deposited-amount: (+ (get deposited-amount investor-position) individual-yield),
        accumulated-rewards: (+ (get accumulated-rewards investor-position) individual-yield),
        last-compound-block: block-height
      })
    )
    
    (print {
      event: "investor-position-compounded",
      investor: tx-sender,
      strategy-id: strategy-id,
      yield-added: individual-yield,
      blocks-held: blocks-held
    })
    
    (ok individual-yield)
  )
)

;; Helper Functions
(define-private (calculate-vault-shares (deposit-amount uint) (total-deposits uint))
  (if (is-eq total-deposits u0)
    deposit-amount ;; First deposit gets 1:1 shares
    (/ (* deposit-amount u1000000) total-deposits) ;; Proportional shares with precision
  )
)

(define-private (calculate-withdrawal-amount (shares uint) (total-shares uint) (total-deposit uint))
  (/ (* shares total-deposit) total-shares)
)

(define-private (calculate-strategy-yield (strategy-id uint) (blocks-elapsed uint))
  (match (map-get? yield-strategies strategy-id)
    strategy-data 
    (let (
      (annual-blocks u52560)
      (target-apy (get target-apy strategy-data))
      (total-deposits (get total-deposits strategy-data))
      (performance-multiplier (get performance-multiplier strategy-data))
    )
      ;; yield = (deposits * apy * blocks_elapsed * multiplier) / (annual_blocks * 10000)
      (/ (* (* (* total-deposits target-apy) blocks-elapsed) performance-multiplier) (* annual-blocks u10000))
    )
    u0
  )
)

(define-private (calculate-individual-yield (strategy-id uint) (investor principal) (blocks-held uint))
  (match (map-get? investor-vault-positions {investor: investor, strategy-id: strategy-id})
    position-data
    (match (map-get? yield-strategies strategy-id)
      strategy-data
      (let (
        (deposited-amount (get deposited-amount position-data))
        (target-apy (get target-apy strategy-data))
        (annual-blocks u52560)
        (performance-multiplier (get performance-multiplier strategy-data))
      )
        (/ (* (* (* deposited-amount target-apy) blocks-held) performance-multiplier) (* annual-blocks u10000))
      )
      u0
    )
    u0
  )
)

;; View Functions
(define-read-only (get-investor-position (investor principal) (strategy-id uint))
  (map-get? investor-vault-positions {investor: investor, strategy-id: strategy-id})
)

(define-read-only (get-strategy-details (strategy-id uint))
  (map-get? yield-strategies strategy-id)
)

(define-read-only (get-protocol-metrics)
  {
    total-value-locked: (var-get total-value-locked),
    performance-fee: (var-get protocol-performance-fee),
    emergency-shutdown: (var-get emergency-shutdown),
    auto-compound-frequency: (var-get auto-compound-frequency),
    strategy-counter: (var-get strategy-counter),
    current-epoch: (var-get current-epoch)
  }
)

(define-read-only (calculate-pending-yield (investor principal) (strategy-id uint))
  (match (map-get? investor-vault-positions {investor: investor, strategy-id: strategy-id})
    position-data
    (let (
      (blocks-since-compound (- block-height (get last-compound-block position-data)))
    )
      (calculate-individual-yield strategy-id investor blocks-since-compound)
    )
    u0
  )
)

(define-read-only (get-strategy-performance (strategy-id uint) (epoch uint))
  (map-get? strategy-performance-history {strategy-id: strategy-id, epoch: epoch})
)

(define-read-only (get-treasury-allocation (allocation-type (string-ascii 32)))
  (default-to u0 (map-get? protocol-treasury-allocation allocation-type))
)

(define-read-only (estimate-strategy-apy (strategy-id uint))
  (match (map-get? yield-strategies strategy-id)
    strategy-data
    (let (
      (total-rewards (get total-rewards-generated strategy-data))
      (total-deposits (get total-deposits strategy-data))
      (performance-multiplier (get performance-multiplier strategy-data))
    )
      (if (> total-deposits u0)
        (/ (* (* total-rewards u10000) performance-multiplier) total-deposits)
        (get target-apy strategy-data)
      )
    )
    u0
  )
)