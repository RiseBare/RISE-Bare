package com.rise.client.security;

import net.schmizz.sshj.userauth.keyprovider.KeyFormat;
import net.schmizz.sshj.userauth.keyprovider.KeyProvider;
import net.schmizz.sshj.userauth.keyprovider.OpenSSHKeyFile;
import net.schmizz.sshj.userauth.keyprovider.PKCS8KeyFile;

import java.io.IOException;
import java.security.KeyPair;

/**
 * SSH Key Provider for RISE Client
 * Handles loading private keys in various formats
 */
public class RiseKeyProvider {

    /**
     * Load a key pair from OpenSSH private key format
     */
    public static KeyPair loadKeyPair(byte[] keyBytes) throws IOException {
        // Try OpenSSH format first
        try {
            OpenSSHKeyFile openssh = new OpenSSHKeyFile();
            openssh.init(new String(keyBytes), "");
            return openssh.getKeyPair();
        } catch (Exception e) {
            // Try PKCS8 format
        }

        try {
            PKCS8KeyFile pkcs8 = new PKCS8KeyFile();
            pkcs8.init(new String(keyBytes), "");
            return pkcs8.getKeyPair();
        } catch (Exception e) {
            throw new IOException("Unable to parse private key", e);
        }
    }

    /**
     * Get supported key formats
     */
    public static KeyFormat[] getSupportedFormats() {
        return new KeyFormat[] { KeyFormat.OPENSSH, KeyFormat.PKCS8 };
    }
}
