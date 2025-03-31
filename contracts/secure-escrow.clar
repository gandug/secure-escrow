;; -----------------------------------------------------
;; SecureEscrow - A Smart Contract for Secure Transactions
;; -----------------------------------------------------
;; This contract facilitates escrow transactions, ensuring
;; funds are only released when both parties agree or an admin intervenes.
;; -----------------------------------------------------

;; ------------------- Constants -------------------
(define-constant CONTRACT-OWNER tx-sender) ;; Contract admin for dispute resolution
(define-constant ERR-UNAUTHORIZED u1000)
(define-constant ERR-NOT-FOUND u1001)
(define-constant ERR-ALREADY-RELEASED u1002)
(define-constant ERR-INVALID-STATE u1003)
(define-constant ERR-TRANSFER-FAILED u1004)
(define-constant ERR-ZERO-AMOUNT u1005)
(define-constant ERR-SELF-ESCROW u1006)

;; Escrow states: 0 = Pending, 1 = Released, 2 = Disputed, 3 = Refunded

;; ------------------- Data Storage -------------------
(define-data-var escrow-counter uint u0)
(define-map escrows { id: uint }
  (tuple
    (buyer principal)
    (seller principal)
    (amount uint)
    (state uint) ;; 0 = Pending, 1 = Released, 2 = Disputed, 3 = Refunded
  ))

;; ------------------- Create Escrow -------------------
(define-public (create-escrow (seller principal) (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (> amount u0) (err ERR-ZERO-AMOUNT))
    (asserts! (not (is-eq tx-sender seller)) (err ERR-SELF-ESCROW))
    
    ;; Transfer funds from buyer to contract
    (match (stx-transfer? amount tx-sender (as-contract tx-sender))
      success
        (let ((escrow-id (+ (var-get escrow-counter) u1)))
          (var-set escrow-counter escrow-id)
          (map-set escrows { id: escrow-id }
            { buyer: tx-sender, seller: seller, amount: amount, state: u0 })
          (ok escrow-id))
      error (err ERR-TRANSFER-FAILED)
    )
  )
)

;; ------------------- Release Funds -------------------
(define-public (release-funds (escrow-id uint))
  (begin
    ;; Safely get escrow data
    (match (map-get? escrows { id: escrow-id })
      escrow
        (begin
          ;; Validate state and authorization
          (asserts! (is-eq tx-sender (get buyer escrow)) (err ERR-UNAUTHORIZED))
          (asserts! (is-eq (get state escrow) u0) (err ERR-ALREADY-RELEASED))
          
          ;; Transfer funds from contract to seller
          (match (as-contract (stx-transfer? (get amount escrow) tx-sender (get seller escrow)))
            success
              (begin
                ;; Update escrow state
                (map-set escrows { id: escrow-id } (merge escrow { state: u1 }))
                (ok true))
            error (err ERR-TRANSFER-FAILED)
          )
        )
      (err ERR-NOT-FOUND)
    )
  )
)

;; ------------------- Raise Dispute -------------------
(define-public (raise-dispute (escrow-id uint))
  (begin
    ;; Safely get escrow data
    (match (map-get? escrows { id: escrow-id })
      escrow
        (begin
          ;; Validate state and authorization
          (asserts! (or (is-eq tx-sender (get buyer escrow)) 
                        (is-eq tx-sender (get seller escrow)))
                    (err ERR-UNAUTHORIZED))
          (asserts! (is-eq (get state escrow) u0) (err ERR-INVALID-STATE))
          
          ;; Update escrow state
          (map-set escrows { id: escrow-id } (merge escrow { state: u2 }))
          (ok true)
        )
      (err ERR-NOT-FOUND)
    )
  )
)

;; ------------------- Resolve Dispute -------------------
(define-public (resolve-dispute (escrow-id uint) (release-to-seller bool))
  (begin
    ;; Only contract owner can resolve disputes
    (asserts! (is-eq tx-sender CONTRACT-OWNER) (err ERR-UNAUTHORIZED))
    
    ;; Safely get escrow data
    (match (map-get? escrows { id: escrow-id })
      escrow
        (begin
          ;; Validate escrow is in disputed state
          (asserts! (is-eq (get state escrow) u2) (err ERR-INVALID-STATE))
          
          ;; Transfer funds based on resolution
          (if release-to-seller
              ;; Release to seller
              (match (as-contract (stx-transfer? (get amount escrow) tx-sender (get seller escrow)))
                success
                  (begin
                    (map-set escrows { id: escrow-id } (merge escrow { state: u1 }))
                    (ok true))
                error (err ERR-TRANSFER-FAILED)
              )
              ;; Refund to buyer
              (match (as-contract (stx-transfer? (get amount escrow) tx-sender (get buyer escrow)))
                success
                  (begin
                    (map-set escrows { id: escrow-id } (merge escrow { state: u3 }))
                    (ok true))
                error (err ERR-TRANSFER-FAILED)
              )
          )
        )
      (err ERR-NOT-FOUND)
    )
  )
)

;; ------------------- Read-Only Functions -------------------
(define-read-only (get-escrow (escrow-id uint))
  (ok (map-get? escrows { id: escrow-id }))
)

(define-read-only (get-escrow-state (escrow-id uint))
  (match (map-get? escrows { id: escrow-id })
    escrow (ok (get state escrow))
    (err ERR-NOT-FOUND)
  )
)

(define-read-only (get-contract-owner)
  (ok CONTRACT-OWNER)
)