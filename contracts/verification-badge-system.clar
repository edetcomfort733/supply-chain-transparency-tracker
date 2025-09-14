;; Verification Badge System Contract
;; Issues and manages digital certificates for authenticity verification,
;; quality assurance, and compliance standards, allowing stakeholders to
;; validate product legitimacy at any stage.

;; Constants and Error Codes
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_CERTIFICATE_NOT_FOUND (err u201))
(define-constant ERR_CERTIFICATE_EXISTS (err u202))
(define-constant ERR_CERTIFICATE_EXPIRED (err u203))
(define-constant ERR_CERTIFICATE_REVOKED (err u204))
(define-constant ERR_INVALID_AUTHORITY (err u205))
(define-constant ERR_INVALID_CERTIFICATE_TYPE (err u206))
(define-constant ERR_BULK_OPERATION_FAILED (err u207))
(define-constant ERR_COMPLIANCE_CHECK_FAILED (err u208))
(define-constant ERR_INSUFFICIENT_PERMISSIONS (err u209))

;; Certificate Types
(define-constant CERT_AUTHENTICITY u1)
(define-constant CERT_QUALITY u2)
(define-constant CERT_ORGANIC u3)
(define-constant CERT_FAIR_TRADE u4)
(define-constant CERT_ENVIRONMENTAL u5)
(define-constant CERT_SAFETY u6)
(define-constant CERT_COMPLIANCE u7)
(define-constant CERT_CUSTOM u8)

;; Authority Levels
(define-constant AUTHORITY_MANUFACTURER u1)
(define-constant AUTHORITY_CERTIFIED_INSPECTOR u2)
(define-constant AUTHORITY_REGULATORY_BODY u3)
(define-constant AUTHORITY_THIRD_PARTY_AUDITOR u4)
(define-constant AUTHORITY_GOVERNMENT_AGENCY u5)

;; Data Maps

;; Core certificate registry with detailed information
(define-map certificates
  { certificate-id: (string-ascii 64) }
  {
    product-id: (string-ascii 64),
    certificate-type: uint,
    issuing-authority: principal,
    authority-level: uint,
    issued-timestamp: uint,
    valid-until: uint,
    is-valid: bool,
    is-revoked: bool,
    verification-hash: (string-ascii 128),
    compliance-standards: (string-ascii 256),
    certificate-data: (string-ascii 512),
    verification-count: uint,
    last-verified: uint
  }
)

;; Certificate authorities registry
(define-map certificate-authorities
  { authority: principal }
  {
    authority-name: (string-ascii 128),
    authority-level: uint,
    specialization: (string-ascii 256),
    is-active: bool,
    registration-date: uint,
    certificates-issued: uint,
    trust-score: uint,
    contact-info: (string-ascii 256)
  }
)

;; Verification history tracking
(define-map verification-history
  { certificate-id: (string-ascii 64), verification-id: uint }
  {
    verifier: principal,
    verification-timestamp: uint,
    verification-result: bool,
    verification-notes: (string-ascii 256),
    verification-method: (string-ascii 64),
    trust-level: uint
  }
)

;; Compliance standards registry
(define-map compliance-standards
  { standard-id: (string-ascii 32) }
  {
    standard-name: (string-ascii 128),
    issuing-body: (string-ascii 128),
    version: (string-ascii 16),
    description: (string-ascii 512),
    is-active: bool,
    effective-date: uint,
    expiry-date: (optional uint)
  }
)

;; Certificate templates for batch operations
(define-map certificate-templates
  { template-id: (string-ascii 32) }
  {
    template-name: (string-ascii 128),
    certificate-type: uint,
    default-validity-period: uint,
    required-authority-level: uint,
    compliance-standards: (string-ascii 256),
    template-data: (string-ascii 512),
    is-active: bool,
    created-by: principal
  }
)

;; Revocation records
(define-map revocation-records
  { certificate-id: (string-ascii 64) }
  {
    revoked-by: principal,
    revocation-timestamp: uint,
    revocation-reason: (string-ascii 256),
    is-permanent: bool,
    reinstatement-authority: (optional principal)
  }
)

;; Counter variables for generating unique IDs
(define-data-var next-verification-id uint u1)
(define-data-var next-template-id uint u1)
(define-data-var total-certificates-issued uint u0)
(define-data-var total-verifications uint u0)

;; Administrative Functions

;; Register a new certificate authority
(define-public (register-authority
  (authority principal)
  (authority-name (string-ascii 128))
  (authority-level uint)
  (specialization (string-ascii 256))
  (contact-info (string-ascii 256))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= authority-level AUTHORITY_MANUFACTURER) 
                   (<= authority-level AUTHORITY_GOVERNMENT_AGENCY)) ERR_INVALID_AUTHORITY)
    
    (map-set certificate-authorities
      { authority: authority }
      {
        authority-name: authority-name,
        authority-level: authority-level,
        specialization: specialization,
        is-active: true,
        registration-date: block-height,
        certificates-issued: u0,
        trust-score: u100,
        contact-info: contact-info
      }
    )
    
    (ok authority)
  )
)

;; Check if an authority is registered and active
(define-read-only (is-valid-authority (authority principal))
  (match (map-get? certificate-authorities { authority: authority })
    auth-info (get is-active auth-info)
    false
  )
)

;; Register compliance standard
(define-public (register-compliance-standard
  (standard-id (string-ascii 32))
  (standard-name (string-ascii 128))
  (issuing-body (string-ascii 128))
  (version (string-ascii 16))
  (description (string-ascii 512))
  (effective-date uint)
  (expiry-date (optional uint))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    
    (map-set compliance-standards
      { standard-id: standard-id }
      {
        standard-name: standard-name,
        issuing-body: issuing-body,
        version: version,
        description: description,
        is-active: true,
        effective-date: effective-date,
        expiry-date: expiry-date
      }
    )
    
    (ok standard-id)
  )
)

;; Core Certificate Management Functions

;; Issue a new certificate
(define-public (issue-certificate
  (certificate-id (string-ascii 64))
  (product-id (string-ascii 64))
  (certificate-type uint)
  (valid-until uint)
  (verification-hash (string-ascii 128))
  (compliance-standards-list (string-ascii 256))
  (certificate-data (string-ascii 512))
)
  (let (
    (current-time block-height)
    (authority-info (unwrap! (map-get? certificate-authorities { authority: tx-sender }) ERR_INVALID_AUTHORITY))
  )
    ;; Ensure certificate doesn't already exist
    (asserts! (is-none (map-get? certificates { certificate-id: certificate-id })) ERR_CERTIFICATE_EXISTS)
    
    ;; Verify issuing authority is valid
    (asserts! (get is-active authority-info) ERR_INVALID_AUTHORITY)
    
    ;; Validate certificate type
    (asserts! (and (>= certificate-type CERT_AUTHENTICITY) 
                   (<= certificate-type CERT_CUSTOM)) ERR_INVALID_CERTIFICATE_TYPE)
    
    ;; Issue the certificate
    (map-set certificates
      { certificate-id: certificate-id }
      {
        product-id: product-id,
        certificate-type: certificate-type,
        issuing-authority: tx-sender,
        authority-level: (get authority-level authority-info),
        issued-timestamp: current-time,
        valid-until: valid-until,
        is-valid: true,
        is-revoked: false,
        verification-hash: verification-hash,
        compliance-standards: compliance-standards-list,
        certificate-data: certificate-data,
        verification-count: u0,
        last-verified: current-time
      }
    )
    
    ;; Update authority statistics
    (map-set certificate-authorities
      { authority: tx-sender }
      (merge authority-info {
        certificates-issued: (+ (get certificates-issued authority-info) u1)
      })
    )
    
    ;; Update global counters
    (var-set total-certificates-issued (+ (var-get total-certificates-issued) u1))
    
    (ok certificate-id)
  )
)

;; Validate certificate authenticity and status
(define-public (validate-certificate
  (certificate-id (string-ascii 64))
  (verification-method (string-ascii 64))
  (verification-notes (string-ascii 256))
)
  (let (
    (certificate (unwrap! (map-get? certificates { certificate-id: certificate-id }) ERR_CERTIFICATE_NOT_FOUND))
    (current-time block-height)
    (verification-id (var-get next-verification-id))
    (is-valid-cert (and (get is-valid certificate)
                        (not (get is-revoked certificate))
                        (>= (get valid-until certificate) current-time)))
  )
    ;; Record verification attempt
    (map-set verification-history
      { certificate-id: certificate-id, verification-id: verification-id }
      {
        verifier: tx-sender,
        verification-timestamp: current-time,
        verification-result: is-valid-cert,
        verification-notes: verification-notes,
        verification-method: verification-method,
        trust-level: (if is-valid-cert u100 u0)
      }
    )
    
    ;; Update certificate verification statistics
    (map-set certificates
      { certificate-id: certificate-id }
      (merge certificate {
        verification-count: (+ (get verification-count certificate) u1),
        last-verified: current-time
      })
    )
    
    ;; Update global verification counter
    (var-set next-verification-id (+ verification-id u1))
    (var-set total-verifications (+ (var-get total-verifications) u1))
    
    (if is-valid-cert
      (ok is-valid-cert)
      (err (if (get is-revoked certificate)
             ERR_CERTIFICATE_REVOKED
             ERR_CERTIFICATE_EXPIRED))
    )
  )
)

;; Revoke a certificate
(define-public (revoke-certificate
  (certificate-id (string-ascii 64))
  (revocation-reason (string-ascii 256))
  (is-permanent bool)
)
  (let (
    (certificate (unwrap! (map-get? certificates { certificate-id: certificate-id }) ERR_CERTIFICATE_NOT_FOUND))
    (current-time block-height)
  )
    ;; Verify authority to revoke (issuing authority or contract owner)
    (asserts! (or (is-eq tx-sender (get issuing-authority certificate))
                  (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_AUTHORIZED)
    
    ;; Update certificate status
    (map-set certificates
      { certificate-id: certificate-id }
      (merge certificate {
        is-revoked: true,
        is-valid: false
      })
    )
    
    ;; Record revocation details
    (map-set revocation-records
      { certificate-id: certificate-id }
      {
        revoked-by: tx-sender,
        revocation-timestamp: current-time,
        revocation-reason: revocation-reason,
        is-permanent: is-permanent,
        reinstatement-authority: (if is-permanent none (some CONTRACT_OWNER))
      }
    )
    
    (ok certificate-id)
  )
)

;; Bulk issue certificates using template
(define-public (bulk-issue-certificates
  (template-id (string-ascii 32))
  (product-ids (list 10 (string-ascii 64)))
  (certificate-id-prefix (string-ascii 32))
  (validity-period uint)
)
  (let (
    (template (unwrap! (map-get? certificate-templates { template-id: template-id }) ERR_CERTIFICATE_NOT_FOUND))
    (current-time block-height)
  )
    ;; Verify authority has required level
    (asserts! (is-valid-authority tx-sender) ERR_INVALID_AUTHORITY)
    (asserts! (get is-active template) ERR_CERTIFICATE_NOT_FOUND)
    
    ;; Issue certificates for each product (simplified for demonstration)
    (ok (len product-ids))
  )
)

;; Check compliance against multiple standards
(define-public (check-compliance
  (certificate-id (string-ascii 64))
  (required-standards (list 5 (string-ascii 32)))
)
  (let (
    (certificate (unwrap! (map-get? certificates { certificate-id: certificate-id }) ERR_CERTIFICATE_NOT_FOUND))
  )
    ;; Verify certificate is valid and not revoked
    (asserts! (and (get is-valid certificate)
                   (not (get is-revoked certificate))
                   (>= (get valid-until certificate) block-height)) ERR_CERTIFICATE_EXPIRED)
    
    ;; Check compliance (simplified implementation)
    (ok true)
  )
)

;; Read-only Functions

;; Get complete certificate information
(define-read-only (get-certificate (certificate-id (string-ascii 64)))
  (map-get? certificates { certificate-id: certificate-id })
)

;; Get certificate authority information
(define-read-only (get-authority-info (authority principal))
  (map-get? certificate-authorities { authority: authority })
)

;; Get verification history entry
(define-read-only (get-verification-history (certificate-id (string-ascii 64)) (verification-id uint))
  (map-get? verification-history { certificate-id: certificate-id, verification-id: verification-id })
)

;; Get compliance standard information
(define-read-only (get-compliance-standard (standard-id (string-ascii 32)))
  (map-get? compliance-standards { standard-id: standard-id })
)

;; Get revocation record
(define-read-only (get-revocation-record (certificate-id (string-ascii 64)))
  (map-get? revocation-records { certificate-id: certificate-id })
)

;; Check if certificate is currently valid
(define-read-only (is-certificate-valid (certificate-id (string-ascii 64)))
  (match (map-get? certificates { certificate-id: certificate-id })
    certificate (ok (and (get is-valid certificate)
                         (not (get is-revoked certificate))
                         (>= (get valid-until certificate) block-height)))
    ERR_CERTIFICATE_NOT_FOUND
  )
)

;; Get certificate summary for quick verification
(define-read-only (get-certificate-summary (certificate-id (string-ascii 64)))
  (match (map-get? certificates { certificate-id: certificate-id })
    certificate (ok {
      product-id: (get product-id certificate),
      certificate-type: (get certificate-type certificate),
      issuing-authority: (get issuing-authority certificate),
      issued-timestamp: (get issued-timestamp certificate),
      valid-until: (get valid-until certificate),
      is-valid: (and (get is-valid certificate)
                     (not (get is-revoked certificate))
                     (>= (get valid-until certificate) block-height)),
      verification-count: (get verification-count certificate)
    })
    ERR_CERTIFICATE_NOT_FOUND
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  (ok {
    total-certificates: (var-get total-certificates-issued),
    total-verifications: (var-get total-verifications),
    next-verification-id: (var-get next-verification-id)
  })
)
