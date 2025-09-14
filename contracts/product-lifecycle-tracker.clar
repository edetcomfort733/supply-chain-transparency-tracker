;; Product Lifecycle Tracker Contract
;; Manages the complete journey of products through the supply chain,
;; recording manufacturing details, transportation events, quality checks,
;; and ownership transfers with immutable timestamps.

;; Constants and Error Codes
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PRODUCT_NOT_FOUND (err u101))
(define-constant ERR_PRODUCT_EXISTS (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_INVALID_LOCATION (err u104))
(define-constant ERR_CUSTODY_TRANSFER_FAILED (err u105))
(define-constant ERR_QUALITY_CHECK_FAILED (err u106))
(define-constant ERR_INVALID_TIMESTAMP (err u107))
(define-constant ERR_INSUFFICIENT_PERMISSIONS (err u108))

;; Product Status Definitions
(define-constant STATUS_REGISTERED u1)
(define-constant STATUS_IN_PRODUCTION u2)
(define-constant STATUS_QUALITY_CHECKED u3)
(define-constant STATUS_IN_TRANSIT u4)
(define-constant STATUS_DELIVERED u5)
(define-constant STATUS_RECALLED u6)

;; Data Maps

;; Main product registry with core product information
(define-map products
  { product-id: (string-ascii 64) }
  {
    manufacturer: principal,
    product-type: (string-ascii 128),
    batch-id: (string-ascii 64),
    manufacturing-date: uint,
    origin: (string-ascii 128),
    current-status: uint,
    current-owner: principal,
    registration-timestamp: uint,
    last-updated: uint,
    total-events: uint,
    is-active: bool
  }
)

;; Detailed event history for each product
(define-map product-events
  { product-id: (string-ascii 64), event-id: uint }
  {
    event-type: (string-ascii 32),
    location: (string-ascii 128),
    timestamp: uint,
    actor: principal,
    status: uint,
    metadata: (string-ascii 256),
    previous-owner: (optional principal),
    new-owner: (optional principal),
    quality-score: (optional uint),
    environmental-conditions: (optional (string-ascii 128))
  }
)

;; Quality control records
(define-map quality-checks
  { product-id: (string-ascii 64), check-id: uint }
  {
    inspector: principal,
    check-type: (string-ascii 64),
    result: bool,
    score: uint,
    notes: (string-ascii 256),
    timestamp: uint,
    certification-level: uint,
    compliance-standards: (string-ascii 128)
  }
)

;; Location tracking with detailed information
(define-map location-updates
  { product-id: (string-ascii 64), location-id: uint }
  {
    latitude: (string-ascii 32),
    longitude: (string-ascii 32),
    address: (string-ascii 256),
    facility-name: (string-ascii 128),
    timestamp: uint,
    temperature: (optional int),
    humidity: (optional uint),
    handler: principal,
    transportation-mode: (string-ascii 32)
  }
)

;; Authorized personnel for different operations
(define-map authorized-personnel
  { user: principal, role: (string-ascii 32) }
  { is-authorized: bool, granted-by: principal, granted-at: uint }
)

;; Custody chain tracking
(define-map custody-chain
  { product-id: (string-ascii 64), transfer-id: uint }
  {
    from-owner: principal,
    to-owner: principal,
    transfer-timestamp: uint,
    transfer-location: (string-ascii 128),
    transfer-reason: (string-ascii 128),
    verification-code: (string-ascii 32),
    is-verified: bool
  }
)

;; Counter variables for generating unique IDs
(define-data-var next-event-id uint u1)
(define-data-var next-check-id uint u1)
(define-data-var next-location-id uint u1)
(define-data-var next-transfer-id uint u1)

;; Administrative functions

;; Grant authorization to personnel for specific roles
(define-public (grant-authorization (user principal) (role (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (ok (map-set authorized-personnel
      { user: user, role: role }
      { is-authorized: true, granted-by: tx-sender, granted-at: block-height }
    ))
  )
)

;; Check if user has specific role authorization
(define-read-only (is-authorized (user principal) (role (string-ascii 32)))
  (default-to false
    (get is-authorized
      (map-get? authorized-personnel { user: user, role: role })
    )
  )
)

;; Core Product Management Functions

;; Register a new product in the system
(define-public (register-product
  (product-id (string-ascii 64))
  (product-type (string-ascii 128))
  (batch-id (string-ascii 64))
  (origin (string-ascii 128))
  (initial-location (string-ascii 128))
  (metadata (string-ascii 256))
)
  (let (
    (current-time block-height)
    (event-id (var-get next-event-id))
  )
    ;; Ensure product doesn't already exist
    (asserts! (is-none (map-get? products { product-id: product-id })) ERR_PRODUCT_EXISTS)
    
    ;; Check authorization
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER)
                  (is-authorized tx-sender "manufacturer")) ERR_NOT_AUTHORIZED)
    
    ;; Register the product
    (map-set products
      { product-id: product-id }
      {
        manufacturer: tx-sender,
        product-type: product-type,
        batch-id: batch-id,
        manufacturing-date: current-time,
        origin: origin,
        current-status: STATUS_REGISTERED,
        current-owner: tx-sender,
        registration-timestamp: current-time,
        last-updated: current-time,
        total-events: u1,
        is-active: true
      }
    )
    
    ;; Record initial registration event
    (map-set product-events
      { product-id: product-id, event-id: event-id }
      {
        event-type: "registration",
        location: initial-location,
        timestamp: current-time,
        actor: tx-sender,
        status: STATUS_REGISTERED,
        metadata: metadata,
        previous-owner: none,
        new-owner: (some tx-sender),
        quality-score: none,
        environmental-conditions: none
      }
    )
    
    ;; Increment event counter
    (var-set next-event-id (+ event-id u1))
    
    (ok product-id)
  )
)

;; Update product location and status
(define-public (update-location
  (product-id (string-ascii 64))
  (new-location (string-ascii 128))
  (latitude (string-ascii 32))
  (longitude (string-ascii 32))
  (facility-name (string-ascii 128))
  (transportation-mode (string-ascii 32))
  (temperature (optional int))
  (humidity (optional uint))
)
  (let (
    (product (unwrap! (map-get? products { product-id: product-id }) ERR_PRODUCT_NOT_FOUND))
    (current-time block-height)
    (location-id (var-get next-location-id))
  )
    ;; Verify authorization
    (asserts! (or (is-eq tx-sender (get current-owner product))
                  (is-authorized tx-sender "logistics")) ERR_NOT_AUTHORIZED)
    
    ;; Update location record
    (map-set location-updates
      { product-id: product-id, location-id: location-id }
      {
        latitude: latitude,
        longitude: longitude,
        address: new-location,
        facility-name: facility-name,
        timestamp: current-time,
        temperature: temperature,
        humidity: humidity,
        handler: tx-sender,
        transportation-mode: transportation-mode
      }
    )
    
    ;; Update product's last-updated timestamp
    (map-set products
      { product-id: product-id }
      (merge product { last-updated: current-time })
    )
    
    ;; Increment location counter
    (var-set next-location-id (+ location-id u1))
    
    (ok location-id)
  )
)

;; Transfer custody of a product
(define-public (transfer-custody
  (product-id (string-ascii 64))
  (new-owner principal)
  (transfer-location (string-ascii 128))
  (transfer-reason (string-ascii 128))
  (verification-code (string-ascii 32))
)
  (let (
    (product (unwrap! (map-get? products { product-id: product-id }) ERR_PRODUCT_NOT_FOUND))
    (current-time block-height)
    (transfer-id (var-get next-transfer-id))
    (event-id (var-get next-event-id))
    (current-owner (get current-owner product))
  )
    ;; Verify current owner or authorized personnel can transfer
    (asserts! (or (is-eq tx-sender current-owner)
                  (is-authorized tx-sender "logistics")) ERR_NOT_AUTHORIZED)
    
    ;; Record custody transfer
    (map-set custody-chain
      { product-id: product-id, transfer-id: transfer-id }
      {
        from-owner: current-owner,
        to-owner: new-owner,
        transfer-timestamp: current-time,
        transfer-location: transfer-location,
        transfer-reason: transfer-reason,
        verification-code: verification-code,
        is-verified: true
      }
    )
    
    ;; Update product ownership
    (map-set products
      { product-id: product-id }
      (merge product {
        current-owner: new-owner,
        last-updated: current-time,
        total-events: (+ (get total-events product) u1)
      })
    )
    
    ;; Record transfer event
    (map-set product-events
      { product-id: product-id, event-id: event-id }
      {
        event-type: "custody_transfer",
        location: transfer-location,
        timestamp: current-time,
        actor: tx-sender,
        status: (get current-status product),
        metadata: transfer-reason,
        previous-owner: (some current-owner),
        new-owner: (some new-owner),
        quality-score: none,
        environmental-conditions: none
      }
    )
    
    ;; Increment counters
    (var-set next-transfer-id (+ transfer-id u1))
    (var-set next-event-id (+ event-id u1))
    
    (ok transfer-id)
  )
)

;; Add quality check record
(define-public (add-quality-check
  (product-id (string-ascii 64))
  (check-type (string-ascii 64))
  (result bool)
  (score uint)
  (notes (string-ascii 256))
  (certification-level uint)
  (compliance-standards (string-ascii 128))
)
  (let (
    (product (unwrap! (map-get? products { product-id: product-id }) ERR_PRODUCT_NOT_FOUND))
    (current-time block-height)
    (check-id (var-get next-check-id))
    (event-id (var-get next-event-id))
  )
    ;; Verify authorization for quality checks
    (asserts! (or (is-eq tx-sender (get manufacturer product))
                  (is-authorized tx-sender "quality_inspector")) ERR_NOT_AUTHORIZED)
    
    ;; Record quality check
    (map-set quality-checks
      { product-id: product-id, check-id: check-id }
      {
        inspector: tx-sender,
        check-type: check-type,
        result: result,
        score: score,
        notes: notes,
        timestamp: current-time,
        certification-level: certification-level,
        compliance-standards: compliance-standards
      }
    )
    
    ;; Update product status if quality check passed
    (map-set products
      { product-id: product-id }
      (merge product {
        current-status: (if result STATUS_QUALITY_CHECKED (get current-status product)),
        last-updated: current-time,
        total-events: (+ (get total-events product) u1)
      })
    )
    
    ;; Record quality check event
    (map-set product-events
      { product-id: product-id, event-id: event-id }
      {
        event-type: "quality_check",
        location: "facility",
        timestamp: current-time,
        actor: tx-sender,
        status: (if result STATUS_QUALITY_CHECKED (get current-status product)),
        metadata: notes,
        previous-owner: none,
        new-owner: none,
        quality-score: (some score),
        environmental-conditions: none
      }
    )
    
    ;; Increment counters
    (var-set next-check-id (+ check-id u1))
    (var-set next-event-id (+ event-id u1))
    
    (ok check-id)
  )
)

;; Update product status
(define-public (update-status
  (product-id (string-ascii 64))
  (new-status uint)
  (metadata (string-ascii 256))
)
  (let (
    (product (unwrap! (map-get? products { product-id: product-id }) ERR_PRODUCT_NOT_FOUND))
    (current-time block-height)
    (event-id (var-get next-event-id))
  )
    ;; Verify authorization
    (asserts! (or (is-eq tx-sender (get current-owner product))
                  (is-authorized tx-sender "status_updater")) ERR_NOT_AUTHORIZED)
    
    ;; Validate status value
    (asserts! (and (>= new-status STATUS_REGISTERED) (<= new-status STATUS_RECALLED)) ERR_INVALID_STATUS)
    
    ;; Update product status
    (map-set products
      { product-id: product-id }
      (merge product {
        current-status: new-status,
        last-updated: current-time,
        total-events: (+ (get total-events product) u1)
      })
    )
    
    ;; Record status change event
    (map-set product-events
      { product-id: product-id, event-id: event-id }
      {
        event-type: "status_update",
        location: "system",
        timestamp: current-time,
        actor: tx-sender,
        status: new-status,
        metadata: metadata,
        previous-owner: none,
        new-owner: none,
        quality-score: none,
        environmental-conditions: none
      }
    )
    
    ;; Increment event counter
    (var-set next-event-id (+ event-id u1))
    
    (ok new-status)
  )
)

;; Read-only functions for data retrieval

;; Get complete product information
(define-read-only (get-product (product-id (string-ascii 64)))
  (map-get? products { product-id: product-id })
)

;; Get product event history
(define-read-only (get-product-event (product-id (string-ascii 64)) (event-id uint))
  (map-get? product-events { product-id: product-id, event-id: event-id })
)

;; Get quality check details
(define-read-only (get-quality-check (product-id (string-ascii 64)) (check-id uint))
  (map-get? quality-checks { product-id: product-id, check-id: check-id })
)

;; Get location update details
(define-read-only (get-location-update (product-id (string-ascii 64)) (location-id uint))
  (map-get? location-updates { product-id: product-id, location-id: location-id })
)

;; Get custody transfer details
(define-read-only (get-custody-transfer (product-id (string-ascii 64)) (transfer-id uint))
  (map-get? custody-chain { product-id: product-id, transfer-id: transfer-id })
)

;; Get current product status
(define-read-only (get-product-status (product-id (string-ascii 64)))
  (match (map-get? products { product-id: product-id })
    product (ok (get current-status product))
    ERR_PRODUCT_NOT_FOUND
  )
)

;; Get current product owner
(define-read-only (get-product-owner (product-id (string-ascii 64)))
  (match (map-get? products { product-id: product-id })
    product (ok (get current-owner product))
    ERR_PRODUCT_NOT_FOUND
  )
)

;; Get product history summary
(define-read-only (get-product-summary (product-id (string-ascii 64)))
  (match (map-get? products { product-id: product-id })
    product (ok {
      manufacturer: (get manufacturer product),
      current-owner: (get current-owner product),
      current-status: (get current-status product),
      registration-date: (get registration-timestamp product),
      last-updated: (get last-updated product),
      total-events: (get total-events product),
      is-active: (get is-active product)
    })
    ERR_PRODUCT_NOT_FOUND
  )
)
