# Cryptographic Bill of Materials (CBOM) Strategy

## 1. What is CBOM

A Cryptographic Bill of Materials (CBOM) is a CycloneDX extension standardized by OWASP that catalogs every cryptographic asset in a software system. Unlike an SBOM, which tracks software dependencies, a CBOM inventories algorithms, protocols, key lengths, certificates, and their relationships to data flows. Each entry maps a cryptographic primitive to the component using it and the protection it provides. The result is a queryable, auditable artifact that turns an otherwise invisible attack surface into a maintained inventory.

## 2. Why Addi Needs It

Addi operates under overlapping frameworks that independently mandate cryptographic accountability.

**SFC CE 007/2018** requires documented encryption mechanisms for all systems handling financial data - treating encryption documentation as a first-class control.

**PCI DSS 4.0** (effective March 2025) introduces Requirement 12.3.3, which mandates a cryptographic inventory covering algorithms, key types, and certificate lifetimes used to protect cardholder data. Without a formal CBOM, Addi cannot demonstrate compliance during a QSA assessment.

**NIST post-quantum migration timeline** sets a 2030–2035 deadline for deprecating classical asymmetric cryptography. Addi must know which services rely on RSA or classical Diffie-Hellman before migration can be planned. A CBOM is the prerequisite artifact.

Beyond compliance, a CBOM provides audit evidence. When the SFC asks "show me every algorithm protecting customer financial data," this document is the answer.

## 3. Addi's CBOM Catalog

| Layer | Algorithm/Protocol | Key Size | Purpose | Component |
|---|---|---|---|---|
| Edge TLS | TLS 1.3 | ECDSA P-256 | Client->CloudFront | CloudFront |
| Origin TLS | TLS 1.3 | ECDSA P-256 | CloudFront->ALB | ALB HTTPS listener |
| Service mesh | WireGuard (Cilium) | Curve25519 | Pod-to-pod encryption | Cilium |
| mTLS certs | ECDSA P-256 | Auto-rotated 720h | Service identity | Cilium PKI |
| Secrets at rest | AES-256-GCM | 256-bit | KMS envelope encryption | AWS KMS |
| EBS volumes | AES-256-XTS | 256-bit | Disk encryption | EBS default encryption |
| S3 objects | AES-256-GCM | 256-bit | Object encryption | S3 SSE-KMS |
| RDS storage | AES-256 | 256-bit | Database encryption | RDS TDE |
| Audit trail | AES-256-GCM | 256-bit | Immutable logs | S3 Object Lock + KMS |
| Image signing | ECDSA P-256 | Via Fulcio | Supply chain integrity | Cosign keyless |
| SBOM signing | ECDSA P-256 | Via Fulcio | SBOM integrity | Cosign attach |
| Password hashing | bcrypt | cost 12 | User passwords | Application |
| Token signing | HMAC-SHA256 | 256-bit | JWT/session tokens | Application |
| CloudTrail digest | SHA-256 | N/A | Log integrity validation | CloudTrail |

## 4. Post-Quantum Readiness

All current algorithms are NIST-approved and secure against classical adversaries. The post-quantum threat horizon requires proactive planning.

NIST finalized its first post-quantum standards in 2024. Migration targets for Addi are **ML-KEM (Kyber)** for key exchange and **ML-DSA (Dilithium)** for digital signatures. AWS and Cilium adoption is expected in the 2026–2028 window.

Immediate action: tag all Dependency-Track entries with `crypto-agility` metadata and flag any service introducing RSA or classical Diffie-Hellman. This surfaces post-quantum exposure at CI time rather than during a future migration sprint.

## 5. Tooling Roadmap

- **Phase 1 (current):** Manual CBOM catalog maintained as this document. Ownership assigned to the platform security team, reviewed quarterly and on each infrastructure change.
- **Phase 2:** Integrate `cryptobom-forge` or `cbomkit` into the CI pipeline for automated cryptographic detection across service codebases. This reduces manual drift and catches net-new algorithm introductions at PR time.
- **Phase 3:** Publish CycloneDX CBOM format (version 1.6+) into Dependency-Track alongside the existing SBOM feeds. At this stage, the CBOM becomes a first-class artifact in the software supply chain with version history and diff capability.

## 6. SFC Audit Mapping

This document directly addresses two regulatory obligations:

**CE 007/2018 Art. 4.1** - "mechanisms of encryption" for information security. The catalog in Section 3 is the primary evidence artifact. It names every encryption mechanism, its algorithm, key material, and the data flow it protects.

**Decreto 2555 Art. 9** - "information security policies." The CBOM feeds into and substantiates Addi's broader security policy documentation by providing the cryptographic foundation layer that policies reference but rarely enumerate.

If the SFC asks "what encryption protects customer data?" - the answer is the table in Section 3. If they ask "how do you know?" - the answer is the tooling roadmap in Section 5 and the CI gates that enforce it.
