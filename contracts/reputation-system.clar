;; Reputation System Contract
;; Manages user ratings, reviews, and trust scores

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-RATING-NOT-FOUND (err u501))
(define-constant ERR-INVALID-RATING (err u502))
(define-constant ERR-ALREADY-RATED (err u503))
(define-constant ERR-CANNOT-RATE-SELF (err u504))

;; Data Variables
(define-data-var next-rating-id uint u1)

;; Data Maps
(define-map ratings uint {
  trip-id: uint,
  rater: principal,
  rated-user: principal,
  rating: uint,
  comment: (string-ascii 200),
  created-at: uint
})

(define-map user-ratings principal {
  total-ratings: uint,
  sum-ratings: uint,
  average-rating: uint
})

(define-map trip-ratings uint {
  passenger-rated: bool,
  driver-rated: bool
})

;; Public Functions

;; Submit rating
(define-public (submit-rating
  (trip-id uint)
  (rated-user principal)
  (rating uint)
  (comment (string-ascii 200)))
  (let ((rating-id (var-get next-rating-id)))
    (asserts! (>= rating u1) ERR-INVALID-RATING)
    (asserts! (<= rating u5) ERR-INVALID-RATING)
    (asserts! (not (is-eq tx-sender rated-user)) ERR-CANNOT-RATE-SELF)

    ;; Check if already rated for this trip
    (let ((trip-rating-data (default-to { passenger-rated: false, driver-rated: false }
                                       (map-get? trip-ratings trip-id))))
      ;; This is a simplified check - in practice, you'd verify the rater's role in the trip
      (asserts! (not (get passenger-rated trip-rating-data)) ERR-ALREADY-RATED)
    )

    ;; Create rating record
    (map-set ratings rating-id {
      trip-id: trip-id,
      rater: tx-sender,
      rated-user: rated-user,
      rating: rating,
      comment: comment,
      created-at: block-height
    })

    ;; Update user's rating statistics
    (let ((current-stats (default-to { total-ratings: u0, sum-ratings: u0, average-rating: u0 }
                                    (map-get? user-ratings rated-user))))
      (let ((new-total (+ (get total-ratings current-stats) u1))
            (new-sum (+ (get sum-ratings current-stats) rating)))
        (let ((new-average (/ new-sum new-total)))
          (map-set user-ratings rated-user {
            total-ratings: new-total,
            sum-ratings: new-sum,
            average-rating: new-average
          })
        )
      )
    )

    ;; Update trip rating status
    (map-set trip-ratings trip-id { passenger-rated: true, driver-rated: false })

    (var-set next-rating-id (+ rating-id u1))
    (ok rating-id)
  )
)

;; Update rating (within 24 blocks)
(define-public (update-rating
  (rating-id uint)
  (new-rating uint)
  (new-comment (string-ascii 200)))
  (let ((rating-data (unwrap! (map-get? ratings rating-id) ERR-RATING-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get rater rating-data)) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-rating u1) ERR-INVALID-RATING)
    (asserts! (<= new-rating u5) ERR-INVALID-RATING)
    (asserts! (<= (- block-height (get created-at rating-data)) u24) ERR-NOT-AUTHORIZED)

    (let ((old-rating (get rating rating-data))
          (rated-user (get rated-user rating-data)))

      ;; Update rating record
      (map-set ratings rating-id (merge rating-data {
        rating: new-rating,
        comment: new-comment
      }))

      ;; Update user's rating statistics
      (let ((current-stats (unwrap! (map-get? user-ratings rated-user) ERR-RATING-NOT-FOUND)))
        (let ((new-sum (+ (- (get sum-ratings current-stats) old-rating) new-rating))
              (total (get total-ratings current-stats)))
          (let ((new-average (/ new-sum total)))
            (map-set user-ratings rated-user (merge current-stats {
              sum-ratings: new-sum,
              average-rating: new-average
            }))
          )
        )
      )

      (ok true)
    )
  )
)

;; Read-only Functions

;; Get rating details
(define-read-only (get-rating (rating-id uint))
  (map-get? ratings rating-id)
)

;; Get user rating statistics
(define-read-only (get-user-rating-stats (user principal))
  (map-get? user-ratings user)
)

;; Get user average rating
(define-read-only (get-user-average-rating (user principal))
  (match (map-get? user-ratings user)
    stats (some (get average-rating stats))
    none
  )
)

;; Check if user has good reputation (>= 4.0 rating)
(define-read-only (has-good-reputation (user principal))
  (match (map-get? user-ratings user)
    stats (>= (get average-rating stats) u4)
    false
  )
)

;; Get total ratings count
(define-read-only (get-total-ratings)
  (- (var-get next-rating-id) u1)
)
