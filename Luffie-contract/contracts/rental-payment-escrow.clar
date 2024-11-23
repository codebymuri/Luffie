
;; title: rental-payment-escrow
;; version:
;; summary:
;; description:

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-initialized (err u101))
(define-constant err-not-initialized (err u102))
(define-constant err-already-paid (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-not-tenant (err u105))
(define-constant err-not-completed (err u106))

;; Define data variables
(define-data-var initialized bool false)
(define-data-var tenant principal 'SP000000000000000000002Q6VF78)
(define-data-var landlord principal 'SP000000000000000000002Q6VF78)
(define-data-var rental-amount uint u0)
(define-data-var security-deposit uint u0)
(define-data-var rental-paid bool false)
(define-data-var deposit-paid bool false)
(define-data-var rental-completed bool false)

;; Initialize the contract
(define-public (initialize (new-tenant principal) (new-landlord principal) (rent uint) (deposit uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get initialized)) err-already-initialized)
    (var-set tenant new-tenant)
    (var-set landlord new-landlord)
    (var-set rental-amount rent)
    (var-set security-deposit deposit)
    (var-set initialized true)
    (ok true)))

;; Pay rent
(define-public (pay-rent)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender (var-get tenant)) err-not-tenant)
    (asserts! (not (var-get rental-paid)) err-already-paid)
    (asserts! (>= (stx-get-balance tx-sender) (var-get rental-amount)) err-insufficient-funds)
    (try! (stx-transfer? (var-get rental-amount) tx-sender (as-contract tx-sender)))
    (var-set rental-paid true)
    (ok true)))

;; Pay security deposit
(define-public (pay-security-deposit)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender (var-get tenant)) err-not-tenant)
    (asserts! (not (var-get deposit-paid)) err-already-paid)
    (asserts! (>= (stx-get-balance tx-sender) (var-get security-deposit)) err-insufficient-funds)
    (try! (stx-transfer? (var-get security-deposit) tx-sender (as-contract tx-sender)))
    (var-set deposit-paid true)
    (ok true)))

;; Mark rental as completed
(define-public (complete-rental)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set rental-completed true)
    (ok true)))

;; Release funds to landlord and return deposit to tenant
(define-public (release-funds)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get rental-completed) err-not-completed)
    (try! (as-contract (stx-transfer? (var-get rental-amount) tx-sender (var-get landlord))))
    (try! (as-contract (stx-transfer? (var-get security-deposit) tx-sender (var-get tenant))))
    (ok true)))

;; Getter functions
(define-read-only (get-rental-amount)
  (var-get rental-amount))

(define-read-only (get-security-deposit)
  (var-get security-deposit))

(define-read-only (get-rental-paid)
  (var-get rental-paid))

(define-read-only (get-deposit-paid)
  (var-get deposit-paid))

(define-read-only (get-rental-completed)
  (var-get rental-completed))