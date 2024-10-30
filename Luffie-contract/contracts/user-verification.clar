;; title: User Verification Contract
;; version: 1.0
;; summary: This contract manages user identity verification, status tracking, and administrative functions for a peer-to-peer rental platform.
;; description: The User Verification Contract enables users to register, request verification, and manage their verification status. 
;; It allows an oracle to confirm or suspend user accounts and provides mechanisms to track user trust scores and verification requests.

;; traits
;;

;; token definitions
;;


;; constants
(define-constant UNVERIFIED u0)
(define-constant PENDING u1)
(define-constant VERIFIED u2)
(define-constant SUSPENDED u3)

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-USER-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-VERIFIED (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-SUSPENDED (err u104))
(define-constant ERR-NOT-VERIFIED (err u105))

;; Define oracle principal
(define-data-var oracle-address principal 'SP000000000000000000002Q6VF78)

;; Data structures
(define-map users
    principal
    {
        status: uint,
        verification-hash: (optional (buff 32)),
        verification-timestamp: uint,
        trust-score: uint,
        suspended-until: uint,
        kyc-data: (string-utf8 500)
    }
)

;; Track verification requests
(define-map verification-requests
    principal
    {
        request-time: uint,
        data-hash: (buff 32),
        status: uint
    }
)

;; Administrative functions
(define-public (set-oracle-address (new-oracle principal))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-UNAUTHORIZED)
        (ok (var-set oracle-address new-oracle))
    )
)

;; User registration
(define-public (register-user (kyc-data (string-utf8 500)))
    (let
        ((user-exists (is-some (map-get? users tx-sender))))
        (asserts! (not user-exists) ERR-ALREADY-VERIFIED)
        (ok (map-set users tx-sender
            {
                status: UNVERIFIED,
                verification-hash: none,
                verification-timestamp: u0,
                trust-score: u0,
                suspended-until: u0,
                kyc-data: kyc-data
            }))
    )
)

;; Submit verification request
(define-public (request-verification (data-hash (buff 32)))
    (let
        ((user (unwrap! (map-get? users tx-sender) ERR-USER-NOT-FOUND)))
        (asserts! (is-eq (get status user) UNVERIFIED) ERR-ALREADY-VERIFIED)
        (ok (map-set verification-requests tx-sender
            {
                request-time: block-height,
                data-hash: data-hash,
                status: PENDING
            }))
    )
)

;; Oracle verification confirmation
(define-public (confirm-verification (user-address principal) 
                                   (verification-hash (buff 32)) 
                                   (trust-score uint))
    (begin
        ;; Only oracle can confirm verification
        (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-UNAUTHORIZED)
        
        ;; Update user status
        (match (map-get? users user-address)
            user
            (ok (map-set users user-address
                {
                    status: VERIFIED,
                    verification-hash: (some verification-hash),
                    verification-timestamp: block-height,
                    trust-score: trust-score,
                    suspended-until: (get suspended-until user),
                    kyc-data: (get kyc-data user)
                }))
            ERR-USER-NOT-FOUND)
    )
)

;; Suspend user
(define-public (suspend-user (user-address principal) (suspension-blocks uint))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-UNAUTHORIZED)
        (match (map-get? users user-address)
            user
            (ok (map-set users user-address
                (merge user {
                    status: SUSPENDED,
                    suspended-until: (+ block-height suspension-blocks)
                })))
            ERR-USER-NOT-FOUND)
    )
)

;; Reactivate suspended user
(define-public (reactivate-user (user-address principal))
    (begin
        (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-UNAUTHORIZED)
        (match (map-get? users user-address)
            user
            (ok (map-set users user-address
                (merge user {
                    status: VERIFIED,
                    suspended-until: u0
                })))
            ERR-USER-NOT-FOUND)
    )
)

;; Read-only functions
(define-read-only (get-user-status (user-address principal))
    (match (map-get? users user-address)
        user (ok (get status user))
        ERR-USER-NOT-FOUND)
)

(define-read-only (get-user-trust-score (user-address principal))
    (match (map-get? users user-address)
        user (ok (get trust-score user))
        ERR-USER-NOT-FOUND)
)

(define-read-only (is-user-verified (user-address principal))
    (match (map-get? users user-address)
        user (ok (and
                    (is-eq (get status user) VERIFIED)
                    (>= block-height (get suspended-until user))))
        ERR-USER-NOT-FOUND)
)

(define-read-only (get-verification-request (user-address principal))
    (map-get? verification-requests user-address)
)

;; Utility functions
(define-private (is-verified (user-address principal))
    (match (map-get? users user-address)
        user (and
                (is-eq (get status user) VERIFIED)
                (>= block-height (get suspended-until user)))
        false)
)

;; Check if user can perform actions
(define-public (check-user-eligibility (user-address principal))
    (let
        ((user (unwrap! (map-get? users user-address) ERR-USER-NOT-FOUND)))
        (asserts! (is-verified user-address) ERR-NOT-VERIFIED)
        (ok true)
    )
)
