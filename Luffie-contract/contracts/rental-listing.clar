;; title: Rental Listing Contract
;; version: 1.0
;; summary: This contract manages the creation, updating, and deactivation of rental item listings in a peer-to-peer rental platform.
;; description: The Rental Listing Contract allows users to create and manage listings for items available for rent. 
;; It ensures that listings are validated, securely stored, and accessible. 
;; Users can create new listings, update their details, deactivate them, and retrieve information about existing listings.

;; traits
;;

;; token definitions
;;

;; constants
(define-constant ERR-NOT-OWNER (err u100))
(define-constant ERR-INVALID-DATES (err u101))
(define-constant ERR-LISTING-NOT-FOUND (err u102))
(define-constant ERR-UNAUTHORIZED (err u103))

;; Data Variables
(define-data-var listing-counter uint u0)

;; Define the listing structure
(define-map listings
    uint
    {
        owner: principal,
        title: (string-utf8 100),
        description: (string-utf8 500),
        price-per-day: uint,
        security-deposit: uint,
        available-from: uint,
        available-until: uint,
        is-active: bool
    }
)

;; Public functions

;; Create a new listing
(define-public (create-listing (title (string-utf8 100)) (description (string-utf8 500)) (price-per-day uint) (security-deposit uint) (available-from uint)  (available-until uint))
    (let
        ((listing-id (var-get listing-counter)))
        
        ;; Validate dates
        (asserts! (> available-until available-from) ERR-INVALID-DATES)
        
        ;; Store the listing
        (map-set listings listing-id
            {
                owner: tx-sender,
                title: title,
                description: description,
                price-per-day: price-per-day,
                security-deposit: security-deposit,
                available-from: available-from,
                available-until: available-until,
                is-active: true
            }
        )
        
        ;; Increment the counter
        (var-set listing-counter (+ listing-id u1))
        
        ;; Return the listing ID
        (ok listing-id)
    )
)

;; Update listing details
(define-public (update-listing (listing-id uint)
                              (title (string-utf8 100))
                              (description (string-utf8 500))
                              (price-per-day uint)
                              (security-deposit uint)
                              (available-from uint)
                              (available-until uint))
    (let
        ((listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND)))
        
        ;; Check ownership
        (asserts! (is-eq tx-sender (get owner listing)) ERR-NOT-OWNER)
        
        ;; Validate dates
        (asserts! (> available-until available-from) ERR-INVALID-DATES)
        
        ;; Update the listing
        (map-set listings listing-id
            {
                owner: (get owner listing),
                title: title,
                description: description,
                price-per-day: price-per-day,
                security-deposit: security-deposit,
                available-from: available-from,
                available-until: available-until,
                is-active: (get is-active listing)
            }
        )
        (ok true)
    )
)

;; Deactivate a listing
(define-public (deactivate-listing (listing-id uint))
    (let
        ((listing (unwrap! (map-get? listings listing-id) ERR-LISTING-NOT-FOUND)))
        
        ;; Check ownership
        (asserts! (is-eq tx-sender (get owner listing)) ERR-NOT-OWNER)
        
        ;; Update the listing's active status
        (map-set listings listing-id
            (merge listing { is-active: false })
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-listing (listing-id uint))
    (map-get? listings listing-id)
)

(define-read-only (get-listing-owner (listing-id uint))
    (match (map-get? listings listing-id)
        listing (ok (get owner listing))
        ERR-LISTING-NOT-FOUND
    )
)

(define-read-only (is-listing-active (listing-id uint))
    (match (map-get? listings listing-id)
        listing (ok (get is-active listing))
        ERR-LISTING-NOT-FOUND
    )
)

(define-read-only (get-listing-count)
    (ok (var-get listing-counter))
)