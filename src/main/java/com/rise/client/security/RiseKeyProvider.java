package com.rise.client.security;

import net.schmizz.sshj.SSHClient;
import net.schmizz.sshj.userauth.keyprovider.KeyProvider;

import java.io.IOException;
import java.io.StringReader;

/**
 * SSH Key Provider for RISE Client
 * Handles loading private keys in various formats
 */
public class RiseKeyProvider {

    /**
     * Load a key pair from OpenSSH private key bytes using SSHClient
     */
    public static KeyProvider loadKeyProvider(SSHClient ssh, byte[] keyBytes) throws IOException {
        return ssh.loadKeys(new String(keyBytes));
    }
}
