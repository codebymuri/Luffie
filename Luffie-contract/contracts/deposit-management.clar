
;; title: deposit-management
;; version:
;; summary:
;; description:

;; Deposit Management Smart Contract

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-initialized (err u101))
(define-constant err-already-initialized (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-not-borrower (err u104))
(define-constant err-not-lender (err u105))
(define-constant err-deposit-not-paid (err u106))
(define-constant err-already-returned (err u107))
(define-constant err-not-returned (err u108))

;; Define data variables
(define-data-var initialized bool false)
(define-data-var borrower principal 'SP000000000000000000002Q6VF78)
(define-data-var lender principal 'SP000000000000000000002Q6VF78)
(define-data-var deposit-amount uint u0)
(define-data-var deposit-paid bool false)
(define-data-var item-returned bool false)

;; Initialize the contract
(define-public (initialize (new-borrower principal) (new-lender principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get initialized)) err-already-initialized)
    (var-set borrower new-borrower)
    (var-set lender new-lender)
    (var-set deposit-amount amount)
    (var-set initialized true)
    (ok true)))

;; Pay security deposit
(define-public (pay-deposit)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender (var-get borrower)) err-not-borrower)
    (asserts! (not (var-get deposit-paid)) err-already-initialized)
    (asserts! (>= (stx-get-balance tx-sender) (var-get deposit-amount)) err-insufficient-funds)
    (try! (stx-transfer? (var-get deposit-amount) tx-sender (as-contract tx-sender)))
    (var-set deposit-paid true)
    (ok true)))

;; Mark item as returned
(define-public (return-item)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender (var-get lender)) err-not-lender)
    (asserts! (var-get deposit-paid) err-deposit-not-paid)
    (asserts! (not (var-get item-returned)) err-already-returned)
    (var-set item-returned true)
    (ok true)))

;; Release full deposit back to borrower
(define-public (release-full-deposit)
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender (var-get lender)) err-not-lender)
    (asserts! (var-get deposit-paid) err-deposit-not-paid)
    (asserts! (var-get item-returned) err-not-returned)
    (try! (as-contract (stx-transfer? (var-get deposit-amount) tx-sender (var-get borrower))))
    (var-set deposit-paid false)
    (ok true)))

;; Allocate funds for damages and return remaining deposit
(define-public (allocate-damages (damage-amount uint))
  (begin
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq tx-sender (var-get lender)) err-not-lender)
    (asserts! (var-get deposit-paid) err-deposit-not-paid)
    (asserts! (var-get item-returned) err-not-returned)
    (asserts! (<= damage-amount (var-get deposit-amount)) err-insufficient-funds)
    (let ((remaining-deposit (- (var-get deposit-amount) damage-amount)))
      (try! (as-contract (stx-transfer? damage-amount tx-sender (var-get lender))))
      (try! (as-contract (stx-transfer? remaining-deposit tx-sender (var-get borrower))))
      (var-set deposit-paid false)
      (ok true))))

;; Getter functions
(define-read-only (get-deposit-amount)
  (var-get deposit-amount))

(define-read-only (get-deposit-paid)
  (var-get deposit-paid))

(define-read-only (get-item-returned)
  (var-get item-returned))

(define-read-only (get-borrower)
  (var-get borrower))

(define-read-only (get-lender)
  (var-get lender))