package com.rise.client.security;

import net.schmizz.sshj.userauth.keyprovider.OpenSSHKeyFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.util.Set;

/**
 * Key Manager for RISE Client
 * V5.9: Secure key storage with proper permissions
 * Supports key generation and OpenSSH format conversion
 */
public class KeyManager {
    private static final Logger LOG = LoggerFactory.getLogger(KeyManager.class);

    private static final Path RISE_DIR = Paths.get(System.getProperty("user.home"), ".rise");
    private static final Path KEYS_DIR = RISE_DIR.resolve("keys");

    /**
     * Initialize secure storage directories
     */
    public static void initializeSecureStorage() throws IOException {
        // Create base directories
        Files.createDirectories(RISE_DIR);
        Files.createDirectories(KEYS_DIR);

        // Set permissions on Unix systems
        if (!System.getProperty("os.name").toLowerCase().contains("windows")) {
            try {
                Set<PosixFilePermission> dirPerms =
                    PosixFilePermissions.fromString("rwx------");
                Files.setPosixFilePermissions(RISE_DIR, dirPerms);
                Files.setPosixFilePermissions(KEYS_DIR, dirPerms);

                LOG.info("Secure key storage initialized at: " + KEYS_DIR);
            } catch (UnsupportedOperationException e) {
                LOG.warn("Posix permissions not supported on this system");
            }
        } else {
            LOG.warn("Windows detected - ensure key directory has restricted permissions");
        }
    }

    /**
     * Generate a new SSH Ed25519 key pair and save in OpenSSH format
     * @return KeyPairData containing private key bytes and public key string
     */
    public static KeyPairData generateKeyPair(String serverId) throws IOException {
        initializeSecureStorage();

        try {
            // Generate Ed25519 key pair
            KeyPairGenerator keyGen = KeyPairGenerator.getInstance("Ed25519");
            keyGen.initialize(256);
            KeyPair keyPair = keyGen.generateKeyPair();

            // Convert to OpenSSH format using SSHJ
            OpenSSHKeyFile sshKeyFile = new OpenSSHKeyFile();
            sshKeyFile.setKeyPair(keyPair);

            String privateKeyOpenSSH = sshKeyFile.getPrivateKey();
            String publicKeyOpenSSH = sshKeyFile.getPublicKey();

            // Save private key with secure permissions
            Path keyFile = KEYS_DIR.resolve(serverId + "_id_ed25519");
            Files.write(keyFile, privateKeyOpenSSH.getBytes());

            if (!System.getProperty("os.name").toLowerCase().contains("windows")) {
                try {
                    Set<PosixFilePermission> keyPerms =
                        PosixFilePermissions.fromString("rw-------");
                    Files.setPosixFilePermissions(keyFile, keyPerms);
                    LOG.info("Private key saved with secure permissions (600): " + keyFile);
                } catch (UnsupportedOperationException e) {
                    LOG.warn("Posix permissions not supported");
                }
            }

            LOG.info("Generated new Ed25519 key pair for server: " + serverId);

            return new KeyPairData(
                privateKeyOpenSSH.getBytes(),
                publicKeyOpenSSH
            );

        } catch (NoSuchAlgorithmException e) {
            throw new IOException("Failed to generate Ed25519 key pair", e);
        }
    }

    /**
     * Save private key with secure permissions (600)
     */
    public static void savePrivateKey(String serverId, byte[] privateKeyBytes) throws IOException {
        initializeSecureStorage();

        Path keyFile = KEYS_DIR.resolve(serverId + "_id_ed25519");
        Files.write(keyFile, privateKeyBytes);

        // Set permissions: rw------- (600)
        if (!System.getProperty("os.name").toLowerCase().contains("windows")) {
            try {
                Set<PosixFilePermission> keyPerms =
                    PosixFilePermissions.fromString("rw-------");
                Files.setPosixFilePermissions(keyFile, keyPerms);

                LOG.info("Private key saved with secure permissions (600): " + keyFile);
            } catch (UnsupportedOperationException e) {
                LOG.warn("Posix permissions not supported on this system");
            }
        }
    }

    /**
     * Load private key
     */
    public static byte[] loadPrivateKey(String serverId) throws IOException {
        Path keyFile = KEYS_DIR.resolve(serverId + "_id_ed25519");

        if (!Files.exists(keyFile)) {
            throw new FileNotFoundException("Key not found: " + keyFile);
        }

        // Verify permissions on Unix
        if (!System.getProperty("os.name").toLowerCase().contains("windows")) {
            try {
                Set<PosixFilePermission> perms = Files.getPosixFilePermissions(keyFile);

                if (perms.contains(PosixFilePermission.GROUP_READ) ||
                    perms.contains(PosixFilePermission.OTHERS_READ)) {
                    throw new SecurityException(
                        "Insecure key permissions! File must be rw------- (600): " + keyFile +
                        "\nRun: chmod 600 " + keyFile);
                }
            } catch (UnsupportedOperationException e) {
                // Posix not supported, skip check
            }
        }

        return Files.readAllBytes(keyFile);
    }

    /**
     * Check if a key exists for a server
     */
    public static boolean keyExists(String serverId) {
        Path keyFile = KEYS_DIR.resolve(serverId + "_id_ed25519");
        return Files.exists(keyFile);
    }

    /**
     * Delete a server's key
     */
    public static void deleteKey(String serverId) throws IOException {
        Path keyFile = KEYS_DIR.resolve(serverId + "_id_ed25519");
        if (Files.exists(keyFile)) {
            Files.delete(keyFile);
            LOG.info("Deleted key for server: " + serverId);
        }
    }

    /**
     * Data class for key pair generation results
     */
    public static class KeyPairData {
        public final byte[] privateKeyBytes;
        public final String publicKeyOpenSSH;

        public KeyPairData(byte[] privateKeyBytes, String publicKeyOpenSSH) {
            this.privateKeyBytes = privateKeyBytes;
            this.publicKeyOpenSSH = publicKeyOpenSSH;
        }
    }
}
