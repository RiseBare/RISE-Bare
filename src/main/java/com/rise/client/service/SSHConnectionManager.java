package com.rise.client.service;

import com.rise.client.model.ServerConfig;
import com.rise.client.security.KeyManager;
import com.rise.client.security.KnownHostsManager;
import net.schmizz.sshj.SSHClient;
import net.schmizz.sshj.transport.verification.HostKeyVerifier;
import net.schmizz.sshj.userauth.keyprovider.KeyProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.StringReader;
import java.security.PublicKey;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;

/**
 * SSH Connection Manager
 * Handles SSH connections with TOFU (Trust On First Use) verification
 * Supports both key authentication and password authentication (for onboarding)
 */
public class SSHConnectionManager {
    private static final Logger LOG = LoggerFactory.getLogger(SSHConnectionManager.class);

    private final ConcurrentHashMap<String, SSHClient> connections = new ConcurrentHashMap<>();
    private final KnownHostsManager knownHostsManager;

    // Callback for new host verification (TOFU)
    private volatile HostKeyVerificationCallback verificationCallback;

    public interface HostKeyVerificationCallback {
        /**
         * Called when a new host key is encountered.
         * @return true to accept and store the key, false to reject
         */
        boolean acceptNewHost(String hostname, String fingerprint, String algorithm);
    }

    public SSHConnectionManager(KnownHostsManager knownHostsManager) {
        this.knownHostsManager = knownHostsManager;
    }

    public void setVerificationCallback(HostKeyVerificationCallback callback) {
        this.verificationCallback = callback;
    }

    /**
     * Connect to a server using SSH key authentication (for established servers)
     */
    public SSHClient connectWithKey(ServerConfig server) throws IOException {
        return connect(server, null);
    }

    /**
     * Connect to a server using password authentication (for onboarding)
     */
    public SSHClient connectWithPassword(ServerConfig server, String password) throws IOException {
        return connect(server, password);
    }

    /**
     * Internal connect method
     */
    private SSHClient connect(ServerConfig server, String password) throws IOException {
        // Check if already connected
        SSHClient existing = connections.get(server.getId());
        if (existing != null && existing.isConnected()) {
            return existing;
        }

        SSHClient ssh = new SSHClient();

        // Add host key verifier with TOFU
        ssh.addHostKeyVerifier(new HostKeyVerifier() {
            @Override
            public boolean verify(String hostname, int port, PublicKey key) {
                String fingerprint = KnownHostsManager.getFingerprint(key);
                String algorithm = KnownHostsManager.getAlgorithm(key);

                String status = knownHostsManager.verifyHostKey(hostname, fingerprint);

                if ("known".equals(status)) {
                    LOG.info("Host key verified for: {}", hostname);
                    return true;
                } else if ("unknown".equals(status)) {
                    // New host - ask user via callback
                    if (verificationCallback != null) {
                        boolean accepted = verificationCallback.acceptNewHost(hostname, fingerprint, algorithm);
                        if (accepted) {
                            knownHostsManager.addOrUpdateHost(hostname, fingerprint, algorithm);
                            LOG.info("New host key accepted and stored for: {}", hostname);
                            return true;
                        }
                    }
                    LOG.warn("New host key rejected for: {}", hostname);
                    return false;
                } else {
                    // Changed key - security risk!
                    LOG.error("HOST KEY CHANGED for {}! Possible MITM attack!", hostname);
                    return false;
                }
            }
        });

        // Connect
        int port = server.getPort() != null ? server.getPort() : 22;
        ssh.connect(server.getHost(), port);

        // Authenticate
        String username = server.getUsername() != null ? server.getUsername() : "rise-admin";

        try {
            if (password != null && !password.isEmpty()) {
                // Password authentication (for onboarding with OTP)
                ssh.authPassword(username, password);
                LOG.info("Authenticated with password to: {}", server.getHost());
            } else {
                // Key authentication
                byte[] keyBytes = KeyManager.loadPrivateKey(server.getId());

                // Load keys from string
                KeyProvider keys = ssh.loadKeys(new String(keyBytes));
                ssh.authPublickey(username, keys);
                LOG.info("Authenticated with SSH key to: {}", server.getHost());
            }
        } catch (Exception e) {
            ssh.disconnect();
            throw new IOException("SSH authentication failed: " + e.getMessage(), e);
        }

        connections.put(server.getId(), ssh);
        LOG.info("Connected to server: {} ({})", server.getName(), server.getHost());

        return ssh;
    }

    /**
     * Connect using key pair directly (for onboarding after key generation)
     */
    public SSHClient connectWithGeneratedKey(ServerConfig server, byte[] privateKeyBytes) throws IOException {
        SSHClient ssh = new SSHClient();

        // Simplified host verifier for onboarding (always accept first time)
        ssh.addHostKeyVerifier(new HostKeyVerifier() {
            @Override
            public boolean verify(String hostname, int port, PublicKey key) {
                String fingerprint = KnownHostsManager.getFingerprint(key);
                String algorithm = KnownHostsManager.getAlgorithm(key);

                if (verificationCallback != null) {
                    boolean accepted = verificationCallback.acceptNewHost(hostname, fingerprint, algorithm);
                    if (accepted) {
                        knownHostsManager.addOrUpdateHost(hostname, fingerprint, algorithm);
                    }
                    return accepted;
                }
                return true; // Allow if no callback (onboarding mode)
            }
        });

        int port = server.getPort() != null ? server.getPort() : 22;
        ssh.connect(server.getHost(), port);

        String username = server.getUsername() != null ? server.getUsername() : "rise-admin";

        try {
            KeyProvider keys = ssh.loadKeys(new String(privateKeyBytes));
            ssh.authPublickey(username, keys);
        } catch (Exception e) {
            ssh.disconnect();
            throw new IOException("Failed to authenticate with generated key", e);
        }

        connections.put(server.getId(), ssh);
        return ssh;
    }

    /**
     * Disconnect from a server
     */
    public void disconnect(String serverId) {
        SSHClient ssh = connections.remove(serverId);
        if (ssh != null && ssh.isConnected()) {
            try {
                ssh.disconnect();
            } catch (IOException e) {
                LOG.warn("Error disconnecting from server", e);
            }
        }
    }

    /**
     * Disconnect all servers
     */
    public void disconnectAll() {
        for (String serverId : connections.keySet().toArray(new String[0])) {
            disconnect(serverId);
        }
    }

    /**
     * Get existing connection or null
     */
    public SSHClient getConnection(String serverId) {
        SSHClient ssh = connections.get(serverId);
        if (ssh != null && ssh.isConnected()) {
            return ssh;
        }
        return null;
    }

    /**
     * Check if connected to a server
     */
    public boolean isConnected(String serverId) {
        return getConnection(serverId) != null;
    }
}
