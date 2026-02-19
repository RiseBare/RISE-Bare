package com.rise.client.security;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.PublicKey;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/**
 * Known Hosts Manager for RISE Client
 * Implements TOFU (Trust On First Use) for SSH host keys
 */
public class KnownHostsManager {
    private static final Logger LOG = LoggerFactory.getLogger(KnownHostsManager.class);

    private static final Path KNOWN_HOSTS_FILE = Paths.get(
        System.getProperty("user.home"), ".rise", "known_hosts.json");

    private final ObjectMapper mapper = new ObjectMapper();
    private Map<String, HostKeyEntry> knownHosts = new HashMap<>();

    public KnownHostsManager() throws IOException {
        loadKnownHosts();
    }

    /**
     * Load known hosts from file
     */
    private void loadKnownHosts() throws IOException {
        if (!Files.exists(KNOWN_HOSTS_FILE)) {
            LOG.info("No known_hosts file found, starting fresh");
            return;
        }

        try {
            JsonNode root = mapper.readTree(KNOWN_HOSTS_FILE.toFile());
            ArrayNode hosts = (ArrayNode) root.get("hosts");

            if (hosts != null) {
                for (JsonNode host : hosts) {
                    String hostname = host.get("hostname").asText();
                    String fingerprint = host.get("fingerprint").asText();
                    String algorithm = host.get("algorithm").asText();
                    knownHosts.put(hostname, new HostKeyEntry(hostname, fingerprint, algorithm));
                }
            }
            LOG.info("Loaded {} known hosts", knownHosts.size());
        } catch (Exception e) {
            LOG.warn("Failed to load known_hosts, starting fresh: {}", e.getMessage());
            knownHosts = new HashMap<>();
        }
    }

    /**
     * Save known hosts to file
     */
    public void saveKnownHosts() throws IOException {
        Path parent = KNOWN_HOSTS_FILE.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }

        ObjectNode root = mapper.createObjectNode();
        ArrayNode hosts = mapper.createArrayNode();

        for (HostKeyEntry entry : knownHosts.values()) {
            ObjectNode hostNode = mapper.createObjectNode();
            hostNode.put("hostname", entry.hostname);
            hostNode.put("fingerprint", entry.fingerprint);
            hostNode.put("algorithm", entry.algorithm);
            hosts.add(hostNode);
        }

        root.set("hosts", hosts);
        mapper.writerWithDefaultPrettyPrinter().writeValue(KNOWN_HOSTS_FILE.toFile(), root);

        LOG.info("Saved {} known hosts", knownHosts.size());
    }

    /**
     * Check if a host is known
     */
    public boolean isHostKnown(String hostname) {
        return knownHosts.containsKey(hostname);
    }

    /**
     * Get stored fingerprint for a host
     */
    public String getStoredFingerprint(String hostname) {
        HostKeyEntry entry = knownHosts.get(hostname);
        return entry != null ? entry.fingerprint : null;
    }

    /**
     * Add or update a host entry
     */
    public void addOrUpdateHost(String hostname, String fingerprint, String algorithm) {
        knownHosts.put(hostname, new HostKeyEntry(hostname, fingerprint, algorithm));
        try {
            saveKnownHosts();
        } catch (IOException e) {
            LOG.error("Failed to save known hosts", e);
        }
    }

    /**
     * Remove a host entry
     */
    public void removeHost(String hostname) {
        knownHosts.remove(hostname);
        try {
            saveKnownHosts();
        } catch (IOException e) {
            LOG.error("Failed to save known hosts", e);
        }
    }

    /**
     * Verify host key against stored fingerprint
     * Returns: "known" if matches, "changed" if different, "unknown" if new
     */
    public String verifyHostKey(String hostname, String fingerprint) {
        if (!knownHosts.containsKey(hostname)) {
            return "unknown";
        }

        String stored = knownHosts.get(hostname).fingerprint;
        return stored.equals(fingerprint) ? "known" : "changed";
    }

    /**
     * Get fingerprint from a PublicKey
     */
    public static String getFingerprint(PublicKey key) {
        byte[] encoded = key.getEncoded();
        // SHA256 fingerprint
        try {
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(encoded);
            return "SHA256:" + Base64.getEncoder().encodeToString(hash);
        } catch (Exception e) {
            LOG.warn("Failed to compute SHA256 fingerprint, using raw", e);
            return "RAW:" + Base64.getEncoder().encodeToString(encoded);
        }
    }

    /**
     * Get key algorithm from key type
     */
    public static String getAlgorithm(PublicKey key) {
        String type = key.getAlgorithm();
        if ("Ed25519".equals(type)) return "ssh-ed25519";
        if ("RSA".equals(type)) return "ssh-rsa";
        if ("DSA".equals(type)) return "ssh-dss";
        if (type.startsWith("EC")) return "ecdsa-sha2-nistp" + (key.getEncoded().length > 90 ? "521" : "256");
        return type;
    }

    /**
     * Host key entry
     */
    private static class HostKeyEntry {
        final String hostname;
        final String fingerprint;
        final String algorithm;

        HostKeyEntry(String hostname, String fingerprint, String algorithm) {
            this.hostname = hostname;
            this.fingerprint = fingerprint;
            this.algorithm = algorithm;
        }
    }
}
