import CryptoKit
import Foundation
import NIOCore
import NIOSSL
import X509

/// Where phone transfer keeps its keys and secrets. Nothing here uses the
/// keychain: a build signed without a Team ID gets a keychain prompt after
/// every rebuild, and the Data Protection keychain needs a paid developer
/// certificate. The Secure Enclave needs neither.
///
/// - The identity key is made inside the Secure Enclave. Its private part
///   never leaves the chip; the file holds only a handle that works on this
///   Mac's Secure Enclave and nowhere else.
/// - The PINs are sealed with ChaCha20-Poly1305 under a key that only this
///   Mac's Secure Enclave can derive. The sealed file is useless elsewhere.
/// - The certificate is public, so it is a plain file.
///
/// The folder is mode 700 and the files mode 600. Any failure stops the
/// feature; nothing falls back to a weaker store.
final class TransferVault {
    enum VaultError: Error {
        case noSecureEnclave
        case unreadable(String)
    }

    let directory: URL
    private let lock = NSLock()
    private var sealingKey: SymmetricKey?
    private var secrets: [String: String] = [:]
    private var loaded = false

    init(directory: URL) {
        self.directory = directory
    }

    static func standard() -> TransferVault {
        TransferVault(directory: Database.supportDirectory.appendingPathComponent("transfer", isDirectory: true))
    }

    private var identityURL: URL { directory.appendingPathComponent("identity.enclave") }
    private var sealURL: URL { directory.appendingPathComponent("seal.enclave") }
    private var certificateURL: URL { directory.appendingPathComponent("certificate.der") }
    private var secretsURL: URL { directory.appendingPathComponent("secrets.sealed") }

    private func prepareDirectory() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Identity

    /// The identity key, made in the Secure Enclave on first use.
    func identityKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw VaultError.noSecureEnclave }
        try prepareDirectory()
        if let handle = try? Data(contentsOf: identityURL) {
            do {
                return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle)
            } catch {
                throw VaultError.unreadable("identity")
            }
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        try write(key.dataRepresentation, to: identityURL)
        return key
    }

    func certificate() -> [UInt8]? {
        (try? Data(contentsOf: certificateURL)).map { [UInt8]($0) }
    }

    func setCertificate(_ der: [UInt8]) throws {
        try prepareDirectory()
        try write(Data(der), to: certificateURL)
    }

    // MARK: Sealed secrets

    /// The key that seals the secrets file: an ECDH agreement of a Secure
    /// Enclave key with its own public key, through HKDF. Only this Mac's
    /// Secure Enclave can compute it.
    private func sealKeyLocked() throws -> SymmetricKey {
        if let sealingKey { return sealingKey }
        guard SecureEnclave.isAvailable else { throw VaultError.noSecureEnclave }
        try prepareDirectory()
        let agreement: SecureEnclave.P256.KeyAgreement.PrivateKey
        if let handle = try? Data(contentsOf: sealURL) {
            do { agreement = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: handle) } catch { throw VaultError.unreadable("seal") }
        } else {
            agreement = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            try write(agreement.dataRepresentation, to: sealURL)
        }
        let shared = try agreement.sharedSecretFromKeyAgreement(with: agreement.publicKey)
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("ClipKeeper transfer".utf8), sharedInfo: Data("secrets v1".utf8), outputByteCount: 32)
        sealingKey = key
        return key
    }

    private func loadLocked() throws {
        guard !loaded else { return }
        let key = try sealKeyLocked()
        if let sealed = try? Data(contentsOf: secretsURL) {
            do {
                let box = try ChaChaPoly.SealedBox(combined: sealed)
                let plain = try ChaChaPoly.open(box, using: key)
                secrets = try JSONDecoder().decode([String: String].self, from: plain)
            } catch {
                throw VaultError.unreadable("secrets")
            }
        }
        loaded = true
    }

    private func saveLocked() throws {
        let key = try sealKeyLocked()
        let plain = try JSONEncoder().encode(secrets)
        let box = try ChaChaPoly.seal(plain, using: key)
        try write(box.combined, to: secretsURL)
    }

    func secret(_ name: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        try loadLocked()
        return secrets[name]
    }

    func setSecret(_ value: String?, for name: String) throws {
        lock.lock(); defer { lock.unlock() }
        try loadLocked()
        secrets[name] = value
        try saveLocked()
    }
}

/// The Mac's identity for transfers: a P-256 key and a self-signed
/// certificate. The fingerprint is the SHA-256 of the certificate DER, which
/// is what LocalSend shows and pins.
struct TransferIdentity {
    enum Key {
        /// A key inside the Secure Enclave. The private part never leaves it.
        case enclave(SecureEnclave.P256.Signing.PrivateKey)
        /// An in-memory key, for tests only.
        case ephemeral(P256.Signing.PrivateKey)
    }

    let key: Key
    let certificateDER: [UInt8]
    let fingerprint: String

    /// Loads the identity, or makes it on first use. The certificate is kept,
    /// so the fingerprint stays the same across launches and rebuilds.
    static func load(vault: TransferVault) throws -> TransferIdentity {
        let enclaveKey = try vault.identityKey()
        let privateKey = Certificate.PrivateKey(enclaveKey)
        // The stored certificate must belong to the current key.
        if let der = vault.certificate(), let cert = try? Certificate(derEncoded: der), cert.publicKey == privateKey.publicKey {
            return TransferIdentity(key: .enclave(enclaveKey), certificateDER: der, fingerprint: LocalSend.fingerprint(ofCertificateDER: der))
        }
        let der = try makeCertificate(privateKey: privateKey)
        try vault.setCertificate(der)
        return TransferIdentity(key: .enclave(enclaveKey), certificateDER: der, fingerprint: LocalSend.fingerprint(ofCertificateDER: der))
    }

    /// An identity that lives only in memory. Tests use it.
    static func ephemeral() throws -> TransferIdentity {
        let p256 = P256.Signing.PrivateKey()
        let der = try makeCertificate(privateKey: Certificate.PrivateKey(p256))
        return TransferIdentity(key: .ephemeral(p256), certificateDER: der, fingerprint: LocalSend.fingerprint(ofCertificateDER: der))
    }

    /// A self-signed certificate with a generic name: the fingerprint carries
    /// the identity, so the name says nothing about the user.
    private static func makeCertificate(privateKey: Certificate.PrivateKey) throws -> [UInt8] {
        let name = try DistinguishedName { CommonName("ClipKeeper") }
        let now = Date()
        var serialBytes = [UInt8](repeating: 0, count: 16)
        for i in serialBytes.indices { serialBytes[i] = UInt8.random(in: 0...255) }
        serialBytes[0] &= 0x7F
        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(bytes: serialBytes),
            publicKey: privateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-3_600),
            notValidAfter: now.addingTimeInterval(10 * 365 * 86_400),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
            },
            issuerPrivateKey: privateKey
        )
        return try cert.serializeAsPEM().derBytes
    }

    /// The server side of TLS: the certificate, and the key as NIOSSL sees it.
    func tlsConfiguration() throws -> TLSConfiguration {
        let certificate = try NIOSSLCertificate(bytes: certificateDER, format: .der)
        let nioKey: NIOSSLPrivateKey
        switch key {
        case .enclave(let enclaveKey):
            nioKey = NIOSSLPrivateKey(customPrivateKey: EnclaveSigner(key: enclaveKey))
        case .ephemeral(let p256):
            nioKey = try NIOSSLPrivateKey(bytes: [UInt8](p256.derRepresentation), format: .der)
        }
        var config = TLSConfiguration.makeServerConfiguration(certificateChain: [.certificate(certificate)], privateKey: .privateKey(nioKey))
        config.minimumTLSVersion = .tlsv12
        config.certificateVerification = .none
        return config
    }
}

/// Signs TLS handshakes with the Secure Enclave key. NIOSSL hands over the
/// message to sign; the Secure Enclave hashes it with SHA-256 and returns the
/// ECDSA signature, sent in DER (X9.62) form.
struct EnclaveSigner: NIOSSLCustomPrivateKey, Hashable {
    let key: SecureEnclave.P256.Signing.PrivateKey
    private let id = UUID()

    var signatureAlgorithms: [SignatureAlgorithm] { [.ecdsaSecp256R1Sha256] }

    func sign(channel: Channel, algorithm: SignatureAlgorithm, data: ByteBuffer) -> EventLoopFuture<ByteBuffer> {
        let promise = channel.eventLoop.makePromise(of: ByteBuffer.self)
        guard algorithm == .ecdsaSecp256R1Sha256 else {
            promise.fail(NIOSSLError.failedToLoadPrivateKey)
            return promise.futureResult
        }
        let bytes = Data(data.readableBytesView)
        let key = self.key
        DispatchQueue.global(qos: .userInitiated).async {
            guard let signature = try? key.signature(for: bytes) else {
                promise.fail(NIOSSLError.failedToLoadPrivateKey)
                return
            }
            let der = signature.derRepresentation
            var out = channel.allocator.buffer(capacity: der.count)
            out.writeBytes(der)
            promise.succeed(out)
        }
        return promise.futureResult
    }

    func decrypt(channel: Channel, data: ByteBuffer) -> EventLoopFuture<ByteBuffer> {
        channel.eventLoop.makeFailedFuture(NIOSSLError.failedToLoadPrivateKey)
    }

    static func == (lhs: EnclaveSigner, rhs: EnclaveSigner) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
