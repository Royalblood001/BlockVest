;; Decentralized Crypto Investment Syndicate

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-PLATFORM-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-STRATEGY (err u3))
(define-constant ERR-ALREADY-EVALUATED (err u4))
(define-constant ERR-WRONG-VALIDATION (err u5))
(define-constant ERR-TIME-LOCKED (err u6))
(define-constant ERR-INSUFFICIENT-STAKE (err u7))
(define-constant ERR-INVALID-INPUT (err u8))

;; Data Variables
(define-data-var platform-admin principal tx-sender)
(define-data-var platform-active bool false)
(define-data-var current-strategy-id uint u0)
(define-data-var investor-entry-stake uint u100000) ;; 0.1 STX
(define-data-var total-investment-pool uint u0)
(define-data-var max-strategy-investment uint u1000000000) ;; Reasonable max investment

;; Investment Strategy Structure
(define-map investment-strategies
    uint
    {
        strategy-name: (string-utf8 256),
        crypto-asset: (string-utf8 256),
        investment-deadline: uint,
        required-investment: uint,
        strategy-validated: bool
    }
)

;; Investor Progress Tracking
(define-map investor-progress
    principal
    {
        current-investment-level: uint,
        completed-strategies: (list 20 uint),
        last-validation-attempt: uint,
        total-strategies-validated: uint
    }
)

;; Investor Validation History
(define-map strategy-validations
    {strategy: uint, investor: principal}
    {
        validation-count: uint,
        validated-at: (optional uint)
    }
)

;; Top Investors
(define-map strategy-top-investors
    uint
    (list 10 {investor: principal, validation-block: uint})
)

;; Input Validation Functions
(define-private (is-platform-admin)
    (is-eq tx-sender (var-get platform-admin)))

(define-private (is-valid-strategy-id (strategy-id uint))
    (and (> strategy-id u0) (<= strategy-id u100)))

(define-private (is-valid-strategy-name (name (string-utf8 256)))
    (and 
        (> (len name) u0) 
        (<= (len name) u256)))

(define-private (is-valid-crypto-asset (asset (string-utf8 256)))
    (and 
        (> (len asset) u0) 
        (<= (len asset) u256)))

(define-private (is-valid-investment-deadline (deadline uint))
    (> deadline block-height))

(define-private (is-valid-required-investment (investment uint))
    (and 
        (> investment u0) 
        (<= investment (var-get max-strategy-investment))))

;; Platform Management Functions
(define-public (initialize-investment-platform)
    (begin
        (asserts! (is-platform-admin) ERR-NOT-AUTHORIZED)
        (var-set platform-active true)
        (var-set current-strategy-id u0)
        (var-set total-investment-pool u0)
        (ok true)))

(define-public (create-investment-strategy
    (strategy-id uint)
    (strategy-name (string-utf8 256))
    (crypto-asset (string-utf8 256))
    (investment-deadline uint)
    (required-investment uint))
    (begin
        ;; Input validation checks
        (asserts! (is-platform-admin) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-strategy-id strategy-id) ERR-INVALID-INPUT)
        (asserts! (is-valid-strategy-name strategy-name) ERR-INVALID-INPUT)
        (asserts! (is-valid-crypto-asset crypto-asset) ERR-INVALID-INPUT)
        (asserts! (is-valid-investment-deadline investment-deadline) ERR-INVALID-INPUT)
        (asserts! (is-valid-required-investment required-investment) ERR-INVALID-INPUT)
        
        ;; Existing logic with validated inputs
        (map-set investment-strategies strategy-id
            {
                strategy-name: strategy-name,
                crypto-asset: crypto-asset,
                investment-deadline: investment-deadline,
                required-investment: required-investment,
                strategy-validated: false
            })
        
        ;; Safe addition with overflow check
        (let ((new-total (+ (var-get total-investment-pool) required-investment)))
            (asserts! (>= new-total (var-get total-investment-pool)) ERR-INVALID-INPUT)
            (var-set total-investment-pool new-total))
        
        (ok true)))

;; Investor Registration
(define-public (register-investor)
    (begin
        (asserts! (var-get platform-active) ERR-PLATFORM-NOT-ACTIVE)
        ;; Require entry stake
        (try! (stx-transfer? (var-get investor-entry-stake) tx-sender (var-get platform-admin)))
        
        (map-set investor-progress tx-sender
            {
                current-investment-level: u0,
                completed-strategies: (list),
                last-validation-attempt: u0,
                total-strategies-validated: u0
            })
        (ok true)))

;; Investment Strategy Validation
(define-public (validate-investment-strategy
    (strategy-id uint)
    (validation-outcome (buff 32)))
    (let (
        (strategy (unwrap! (map-get? investment-strategies strategy-id) ERR-INVALID-STRATEGY))
        (investor (unwrap! (map-get? investor-progress tx-sender) ERR-INVALID-STRATEGY))
        )
        ;; Check platform availability
        (asserts! (var-get platform-active) ERR-PLATFORM-NOT-ACTIVE)
        (asserts! (>= block-height (get investment-deadline strategy)) ERR-TIME-LOCKED)
        (asserts! (not (get strategy-validated strategy)) ERR-ALREADY-EVALUATED)
        
        ;; Verify validation - directly compare the outcomes
        (if (is-eq validation-outcome 0x01)  ;; Simplified binary outcome
            (begin
                ;; Update strategy status
                (map-set investment-strategies strategy-id
                    (merge strategy {strategy-validated: true}))
                
                ;; Update investor progress
                (map-set investor-progress tx-sender
                    (merge investor {
                        current-investment-level: (+ strategy-id u1),
                        completed-strategies: (unwrap! (as-max-len? 
                            (append (get completed-strategies investor) strategy-id) u20)
                            ERR-INVALID-STRATEGY),
                        total-strategies-validated: (+ (get total-strategies-validated investor) u1)
                    }))
                
                ;; Record validation
                (map-set strategy-validations
                    {strategy: strategy-id, investor: tx-sender}
                    {
                        validation-count: u1,
                        validated-at: (some block-height)
                    })
                
                ;; Award strategy investment
                (try! (stx-transfer? (get required-investment strategy) (var-get platform-admin) tx-sender))
                
                ;; Record top investors
                (match (map-get? strategy-top-investors strategy-id)
                    top-investors (map-set strategy-top-investors strategy-id
                        (unwrap! (as-max-len?
                            (append top-investors {investor: tx-sender, validation-block: block-height})
                            u10)
                            ERR-INVALID-STRATEGY))
                    (map-set strategy-top-investors strategy-id
                        (list {investor: tx-sender, validation-block: block-height})))
                
                (ok true))
            ERR-WRONG-VALIDATION)))

;; Read-only functions
(define-read-only (get-current-strategy-details (strategy-id uint))
    (match (map-get? investment-strategies strategy-id)
        strategy (if (>= block-height (get investment-deadline strategy))
            (ok (get strategy-name strategy))
            ERR-TIME-LOCKED)
        ERR-INVALID-STRATEGY))

(define-read-only (get-investor-status (investor principal))
    (map-get? investor-progress investor))

(define-read-only (get-strategy-top-investors (strategy-id uint))
    (map-get? strategy-top-investors strategy-id))

(define-read-only (get-platform-stats)
    {
        active: (var-get platform-active),
        current-strategy-id: (var-get current-strategy-id),
        total-investment-pool: (var-get total-investment-pool),
        investor-entry-stake: (var-get investor-entry-stake)
    })