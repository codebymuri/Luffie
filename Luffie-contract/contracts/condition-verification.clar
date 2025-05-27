
;; title: condition-verification
;; version:
;; summary:
;; description:

;; Condition Verification Smart Contract for Rentals

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u403))
(define-constant err-already-rented (err u404))
(define-constant err-not-rented (err u405))
(define-constant err-not-found (err u404))
(define-constant err-already-disputed (err u406))
(define-constant err-not-disputed (err u407))

;; Define data maps
(define-map rentals
  { rental-id: uint }
  {
    renter: principal,
    owner: principal,
    item-id: uint,
    start-time: uint,
    end-time: uint,
    initial-condition: (optional (buff 32)),
    final-condition: (optional (buff 32)),
    status: (string-ascii 20)
  }
)

(define-map items
  { item-id: uint }
  { owner: principal }
)

(define-map disputes
  { rental-id: uint }
  {
    initiator: principal,
    owner-evidence: (optional (buff 32)),
    renter-evidence: (optional (buff 32)),
    resolution: (optional (string-ascii 20))
  }
)

;; Define data vars
(define-data-var next-rental-id uint u1)
(define-data-var next-item-id uint u1)

;; Function to register a new item
(define-public (register-item)
  (let
    ((item-id (var-get next-item-id)))
    (map-insert items
      { item-id: item-id }
      { owner: tx-sender }
    )
    (var-set next-item-id (+ item-id u1))
    (ok item-id)
  )
)

;; Function to start a rental
(define-public (start-rental (item-id uint))
  (let
    (
      (rental-id (var-get next-rental-id))
      (item (unwrap! (map-get? items { item-id: item-id }) err-not-found))
    )
    (asserts! (is-eq (get owner item) tx-sender) err-unauthorized)
    (map-insert rentals
      { rental-id: rental-id }
      {
        renter: tx-sender,
        owner: tx-sender,
        item-id: item-id,
        start-time: block-height,
        end-time: u0,
        initial-condition: none,
        final-condition: none,
        status: "started"
      }
    )
    (var-set next-rental-id (+ rental-id u1))
    (ok rental-id)
  )
)

;; Function to submit initial condition report
(define-public (submit-initial-condition (rental-id uint) (condition-hash (buff 32)))
  (let
    ((rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found)))
    (asserts! (is-eq (get status rental) "started") err-already-rented)
    (asserts! (is-eq (get owner rental) tx-sender) err-unauthorized)
    (map-set rentals
      { rental-id: rental-id }
      (merge rental {
        initial-condition: (some condition-hash),
        status: "in-progress"
      })
    )
    (ok true)
  )
)

;; Function to submit final condition report
(define-public (submit-final-condition (rental-id uint) (condition-hash (buff 32)))
  (let
    ((rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found)))
    (asserts! (is-eq (get status rental) "in-progress") err-not-rented)
    (asserts! (is-eq (get renter rental) tx-sender) err-unauthorized)
    (map-set rentals
      { rental-id: rental-id }
      (merge rental {
        final-condition: (some condition-hash),
        status: "completed",
        end-time: block-height
      })
    )
    (ok true)
  )
)

;; Function to get rental details
(define-read-only (get-rental-details (rental-id uint))
  (map-get? rentals { rental-id: rental-id })
)

;; Function to initiate a dispute
(define-public (initiate-dispute (rental-id uint))
  (let
    ((rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found)))
    (asserts! (or (is-eq (get owner rental) tx-sender) (is-eq (get renter rental) tx-sender)) err-unauthorized)
    (asserts! (is-eq (get status rental) "completed") err-not-rented)
    (asserts! (is-none (map-get? disputes { rental-id: rental-id })) err-already-disputed)
    (map-insert disputes
      { rental-id: rental-id }
      {
        initiator: tx-sender,
        owner-evidence: none,
        renter-evidence: none,
        resolution: none
      }
    )
    (map-set rentals
      { rental-id: rental-id }
      (merge rental { status: "disputed" })
    )
    (ok true)
  )
)

;; Function to submit evidence for a dispute
(define-public (submit-dispute-evidence (rental-id uint) (evidence-hash (buff 32)))
  (let
    ((rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found))
     (dispute (unwrap! (map-get? disputes { rental-id: rental-id }) err-not-disputed)))
    (asserts! (or (is-eq (get owner rental) tx-sender) (is-eq (get renter rental) tx-sender)) err-unauthorized)
    (if (is-eq (get owner rental) tx-sender)
      (map-set disputes
        { rental-id: rental-id }
        (merge dispute { owner-evidence: (some evidence-hash) })
      )
      (map-set disputes
        { rental-id: rental-id }
        (merge dispute { renter-evidence: (some evidence-hash) })
      )
    )
    (ok true)
  )
)

;; Function to resolve a dispute (only contract owner can do this)
(define-public (resolve-dispute (rental-id uint) (resolution (string-ascii 20)))
  (let
    ((rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found))
     (dispute (unwrap! (map-get? disputes { rental-id: rental-id }) err-not-disputed)))
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (map-set disputes
      { rental-id: rental-id }
      (merge dispute { resolution: (some resolution) })
    )
    (map-set rentals
      { rental-id: rental-id }
      (merge rental { status: "resolved" })
    )
    (ok true)
  )
)

;; Function to get dispute details
(define-read-only (get-dispute-details (rental-id uint))
  (map-get? disputes { rental-id: rental-id })
)

