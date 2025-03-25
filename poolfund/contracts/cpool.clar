;; Decentralized Crypto Investment Syndicate - MVP Version
;; Initial basic implementation of collaborative investment platform

(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-PLATFORM-NOT-ACTIVE (err u2))
(define-constant ERR-INVALID-STRATEGY (err u3))

(define-data-var platform-admin principal tx-sender)
(define-data-var platform-active bool false)
(define-data-var current-strategy-id uint u0)

(define-map investment-strategies
    uint
    {
        strategy-name: (string-utf8 100),
        crypto-asset: (string-utf8 50),
        target-investment: uint
    }
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
                    target-investment: target-investment
                })
            (var-set current-strategy-id new-strategy-id)
            (ok new-strategy-id))))

(define-read-only (get-strategy-details (strategy-id uint))
    (map-get? investment-strategies strategy-id))

(define-read-only (get-platform-status)
    {
        active: (var-get platform-active),
        total-strategies: (var-get current-strategy-id)
    })
    