;; Decentralized Crypto Investment Syndicate - Enhanced Version
;; Advanced investment strategy platform with investor tracking and validation

(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-PLATFORM-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-STRATEGY (err u3))
(define-constant ERR-INSUFFICIENT-FUNDS (err u4))

(define-data-var platform-admin principal tx-sender)
(define-data-var platform-active bool false)
(define-data-var current-strategy-id uint u0)
(define-data-var minimum-investment-threshold uint u10000) ;; 0.1 STX

(define-map investment-strategies
    uint
    {
        strategy-name: (string-utf8 100),
        crypto-asset: (string-utf8 50),
        target-investment: uint,
        total-raised: uint,
        strategy-status: (string-utf8 20)
    }
)

(define-map investor-contributions
    {strategy-id: uint, investor: principal}
    uint
)

(define-public (initialize-platform)
    (begin
        (asserts! (is-eq tx-sender (var-get platform-admin)) ERR-NOT-AUTHORIZED)
        (var-set platform-active true)
        (ok true)))

(define-public (create-investment-strategy
    (strategy-name (string-utf8 100))
    (crypto-asset (string-utf8 50))
    (target-investment uint))
    (begin
        (asserts! (var-get platform-active) ERR-PLATFORM-NOT-ACTIVE)
        (let ((new-strategy-id (+ (var-get current-strategy-id) u1)))
            (map-set investment-strategies new-strategy-id
                {
                    strategy-name: strategy-name,
                    crypto-asset: crypto-asset,
                    target-investment: target-investment,
                    total-raised: u0,
                    strategy-status: "OPEN"
                })
            (var-set current-strategy-id new-strategy-id)
            (ok new-strategy-id))))

(define-public (contribute-to-strategy
    (strategy-id uint)
    (contribution-amount uint))
    (let ((strategy (unwrap! (map-get? investment-strategies strategy-id) ERR-INVALID-STRATEGY)))
        (asserts! (var-get platform-active) ERR-PLATFORM-NOT-ACTIVE)
        (asserts! (is-eq (get strategy-status strategy) "OPEN") ERR-INVALID-STRATEGY)
        (asserts! (>= contribution-amount (var-get minimum-investment-threshold)) ERR-INSUFFICIENT-FUNDS)
        
        ;; Transfer STX
        (try! (stx-transfer? contribution-amount tx-sender (var-get platform-admin)))
        
        ;; Update individual contribution
        (let ((current-contribution (default-to u0 (map-get? investor-contributions {strategy-id: strategy-id, investor: tx-sender})))
              (new-contribution (+ current-contribution contribution-amount))
              (new-total-raised (+ (get total-raised strategy) contribution-amount)))
            
            (map-set investor-contributions 
                {strategy-id: strategy-id, investor: tx-sender} 
                new-contribution)
            
            (map-set investment-strategies strategy-id
                (merge strategy {total-raised: new-total-raised}))
            
            (ok true))))

(define-read-only (get-strategy-details (strategy-id uint))
    (map-get? investment-strategies strategy-id))

(define-read-only (get-investor-contribution (strategy-id uint) (investor principal))
    (map-get? investor-contributions {strategy-id: strategy-id, investor: investor}))

(define-read-only (get-platform-status)
    {
        active: (var-get platform-active),
        total-strategies: (var-get current-strategy-id),
        minimum-investment: (var-get minimum-investment-threshold)
    })