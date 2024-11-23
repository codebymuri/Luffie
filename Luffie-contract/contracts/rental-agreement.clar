;; title: rental-agreement
;; version: 1.0
;; summary: A smart contract for managing rental agreements, including terms, payments, and dispute resolution.
;; description: This contract facilitates the creation and management of rental agreements between lenders and renters. 
;; It handles agreement lifecycle, payment processing, dispute initiation, and status management.

;; Traits
;; Define trait for listing contract
(define-trait listing-trait
    (
        (get-listing (uint) (response {
            owner: principal,
            price-per-day: uint,
            security-deposit: uint,
            title: (string-utf8 100),
            description: (string-utf8 500),
            available-from: uint,
            available-until: uint,
            is-active: bool
        } uint))
        (update-listing-status (uint bool) (response bool uint))
    )
)

;; Constants for agreement status
(define-constant PENDING u0)
(define-constant ACTIVE u1)
(define-constant COMPLETED u2)
(define-constant CANCELLED u3)
(define-constant DISPUTED u4)

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-LISTING (err u101))
(define-constant ERR-INVALID-DATES (err u102))
(define-constant ERR-AGREEMENT-NOT-FOUND (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-ALREADY-EXISTS (err u106))
(define-constant ERR-INACTIVE-LISTING (err u107))
(define-constant ERR-DATE-UNAVAILABLE (err u108))
(define-constant ERR-ALREADY-SIGNED (err u109))
(define-constant ERR-NOT-SIGNED (err u110))
(define-constant ERR-DEPOSIT-NOT-PAID (err u111))

;; Agreement counter
(define-data-var agreement-counter uint u0)

;; Store listing contract address
(define-data-var listing-contract-address principal 'SP000000000000000000002Q6VF78)

;; Define agreement structure
(define-map rental-agreements
    uint  ;; agreement ID
    {
        listing-id: uint,
        lender: principal,
        renter: principal,
        start-date: uint,
        end-date: uint,
        daily-rate: uint,
        security-deposit: uint,
        late-fee-rate: uint,
        status: uint,
        terms-hash: (buff 32),
        renter-signed: bool,
        lender-signed: bool,
        total-amount: uint,
        paid-amount: uint,
        refunded-amount: uint,
        created-at: uint,
        updated-at: uint,
        dispute-reason: (optional (string-utf8 500)),
        cancellation-reason: (optional (string-utf8 500))
    }
)

;; Track agreement payments
(define-map agreement-payments
    uint  ;; agreement ID
    {
        deposit-paid: bool,
        deposit-amount: uint,
        rental-paid: bool,
        rental-amount: uint,
        deposit-returned: bool,
        late-fees-paid: uint,
        last-payment-date: uint,
        refund-amount: uint
    }
)

;; Admin functions
(define-public (set-listing-contract (new-address principal))
    (begin
        (asserts! (is-eq tx-sender (var-get listing-contract-address)) ERR-UNAUTHORIZED)
        (ok (var-set listing-contract-address new-address))
    )
)

(define-public (create-agreement (listing-contract <listing-trait>)
                               (listing-id uint)
                               (start-date uint)
                               (end-date uint)
                               (terms-hash (buff 32)))
    (let
        ((listing-response (try! (contract-call? listing-contract get-listing listing-id)))
         (agreement-id (var-get agreement-counter))
         (daily-rate (get price-per-day listing-response))
         (security-deposit (get security-deposit listing-response))
         (rental-days (- end-date start-date))
         (total-amount (* daily-rate rental-days)))
        
        ;; Validate all conditions
        (asserts! (> end-date start-date) ERR-INVALID-DATES)
        (asserts! (>= start-date block-height) ERR-INVALID-DATES)
        (asserts! (get is-active listing-response) ERR-INACTIVE-LISTING)
        (asserts! (and 
                    (>= start-date (get available-from listing-response))
                    (<= end-date (get available-until listing-response)))
                 ERR-DATE-UNAVAILABLE)
        
        ;; Create agreement
        (map-set rental-agreements agreement-id
            {
                listing-id: listing-id,
                lender: (get owner listing-response),
                renter: tx-sender,
                start-date: start-date,
                end-date: end-date,
                daily-rate: daily-rate,
                security-deposit: security-deposit,
                late-fee-rate: u5, ;; 5% daily late fee
                status: PENDING,
                terms-hash: terms-hash,
                renter-signed: false,
                lender-signed: false,
                total-amount: total-amount,
                paid-amount: u0,
                refunded-amount: u0,
                created-at: block-height,
                updated-at: block-height,
                dispute-reason: none,
                cancellation-reason: none
            })
        
        ;; Initialize payments tracking
        (map-set agreement-payments agreement-id
            {
                deposit-paid: false,
                deposit-amount: security-deposit,
                rental-paid: false,
                rental-amount: total-amount,
                deposit-returned: false,
                late-fees-paid: u0,
                last-payment-date: block-height,
                refund-amount: u0
            })
        
        ;; Increment counter
        (var-set agreement-counter (+ agreement-id u1))
        
        (ok agreement-id)
    )
)

;; Sign agreement
(define-public (sign-agreement (agreement-id uint))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        ;; Verify signer is involved in agreement
        (asserts! (or
            (is-eq tx-sender (get lender agreement))
            (is-eq tx-sender (get renter agreement)))
            ERR-UNAUTHORIZED)
        
        ;; Verify agreement is in PENDING status
        (asserts! (is-eq (get status agreement) PENDING) ERR-INVALID-STATUS)
        
        ;; Update signatures
        (map-set rental-agreements agreement-id
            (merge agreement
                {
                    lender-signed: (if (is-eq tx-sender (get lender agreement))
                                     true
                                     (get lender-signed agreement)),
                    renter-signed: (if (is-eq tx-sender (get renter agreement))
                                    true
                                    (get renter-signed agreement)),
                    updated-at: block-height
                }
            )
        )
        
        (ok true)
    )
)

;; Pay security deposit
(define-public (pay-security-deposit (agreement-id uint))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND))
         (payments (unwrap! (map-get? agreement-payments agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        ;; Verify renter and agreement status
        (asserts! (is-eq tx-sender (get renter agreement)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status agreement) PENDING) ERR-INVALID-STATUS)
        (asserts! (is-agreement-signed agreement-id) ERR-NOT-SIGNED)
        
        ;; Update payment status
        (map-set agreement-payments agreement-id
            (merge payments { 
                deposit-paid: true,
                last-payment-date: block-height 
            }))
        
        ;; Activate agreement if conditions met
        (if (and (get lender-signed agreement) (get renter-signed agreement))
            (map-set rental-agreements agreement-id
                (merge agreement {
                    status: ACTIVE,
                    updated-at: block-height
                }))
            false)
        
        (ok true)
    )
)

;; Pay rental amount
(define-public (pay-rental-amount (agreement-id uint))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND))
         (payments (unwrap! (map-get? agreement-payments agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        ;; Verify renter and payment conditions
        (asserts! (is-eq tx-sender (get renter agreement)) ERR-UNAUTHORIZED)
        (asserts! (get deposit-paid payments) ERR-DEPOSIT-NOT-PAID)
        (asserts! (is-eq (get status agreement) ACTIVE) ERR-INVALID-STATUS)
        
        ;; Update payment status
        (map-set agreement-payments agreement-id
            (merge payments { 
                rental-paid: true,
                last-payment-date: block-height
            }))
        
        (ok true)
    )
)

;; Complete rental
(define-public (complete-rental (listing-contract <listing-trait>) 
                              (agreement-id uint))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND))
         (payments (unwrap! (map-get? agreement-payments agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        ;; Verify lender and agreement status
        (asserts! (is-eq tx-sender (get lender agreement)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status agreement) ACTIVE) ERR-INVALID-STATUS)
        (asserts! (get rental-paid payments) ERR-INSUFFICIENT-FUNDS)
        
        ;; Update listing availability
        (try! (contract-call? listing-contract 
               update-listing-status 
               (get listing-id agreement) 
               true))
        
        ;; Update agreement status
        (map-set rental-agreements agreement-id
            (merge agreement {
                status: COMPLETED,
                updated-at: block-height
            }))
        
        (ok true)
    )
)

;; Initiate dispute
(define-public (initiate-dispute (agreement-id uint) 
                               (reason (string-utf8 500)))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        ;; Verify participant and status
        (asserts! (or
            (is-eq tx-sender (get lender agreement))
            (is-eq tx-sender (get renter agreement)))
            ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status agreement) ACTIVE) ERR-INVALID-STATUS)
        
        ;; Update agreement status
        (map-set rental-agreements agreement-id
            (merge agreement {
                status: DISPUTED,
                dispute-reason: (some reason),
                updated-at: block-height
            }))
        
        (ok true)
    )
)

;; Cancel agreement
(define-public (cancel-agreement (listing-contract <listing-trait>)
                               (agreement-id uint)
                               (reason (string-utf8 500)))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        ;; Verify participant
        (asserts! (or
            (is-eq tx-sender (get lender agreement))
            (is-eq tx-sender (get renter agreement)))
            ERR-UNAUTHORIZED)
        
        ;; Update listing availability
        (try! (contract-call? listing-contract 
               update-listing-status 
               (get listing-id agreement) 
               true))
        
        ;; Update agreement status
        (map-set rental-agreements agreement-id
            (merge agreement {
                status: CANCELLED,
                cancellation-reason: (some reason),
                updated-at: block-height
            }))
        
        (ok true)
    )
)

;; Calculate late fees
(define-public (calculate-late-fees (agreement-id uint))
    (let
        ((agreement (unwrap! (map-get? rental-agreements agreement-id) ERR-AGREEMENT-NOT-FOUND)))
        
        (if (> block-height (get end-date agreement))
            (let
                ((days-late (- block-height (get end-date agreement)))
                 (daily-penalty (* (get daily-rate agreement) 
                                 (get late-fee-rate agreement) 
                                 u1)))
                (ok (* days-late daily-penalty)))
            (ok u0)
        )
    )
)

;; Read-only functions
(define-read-only (get-agreement (agreement-id uint))
    (map-get? rental-agreements agreement-id)
)

(define-read-only (get-agreement-payments (agreement-id uint))
    (map-get? agreement-payments agreement-id)
)

(define-read-only (is-agreement-active (agreement-id uint))
    (match (map-get? rental-agreements agreement-id)
        agreement (ok (is-eq (get status agreement) ACTIVE))
        ERR-AGREEMENT-NOT-FOUND)
)

(define-read-only (get-agreement-status (agreement-id uint))
    (match (map-get? rental-agreements agreement-id)
        agreement (ok (get status agreement))
        ERR-AGREEMENT-NOT-FOUND)
)

(define-read-only (get-total-owed (agreement-id uint))
    (match (map-get? rental-agreements agreement-id)
        agreement 
        (let
            ((late-fees (unwrap-panic (calculate-late-fees agreement-id))))
            (ok (+ (get total-amount agreement) late-fees)))
        ERR-AGREEMENT-NOT-FOUND)
)

;; Private helper functions
(define-private (is-agreement-signed (agreement-id uint))
    (match (map-get? rental-agreements agreement-id)
        agreement (and
                    (get lender-signed agreement)
                    (get renter-signed agreement))
        false)
)

(define-private (calculate-total-amount (daily-rate uint) (start-date uint) 
(end-date uint))
    (* daily-rate (- end-date start-date))
)
