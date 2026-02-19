package com.rise.client.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * Represents a server configuration stored in config.json
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class ServerConfig {
    private String id;
    private String name;
    private String host;
    private Integer port = 22;
    private String username = "rise-admin";
    private String knownHostFingerprint;

    // Transient - not saved to config
    @JsonIgnore
    private String password;

    public ServerConfig() {}

    public ServerConfig(String id, String name, String host) {
        this.id = id;
        this.name = name;
        this.host = host;
    }

    // Getters and Setters
    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getHost() { return host; }
    public void setHost(String host) { this.host = host; }

    public Integer getPort() { return port; }
    public void setPort(Integer port) { this.port = port; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getKnownHostFingerprint() { return knownHostFingerprint; }
    public void setKnownHostFingerprint(String knownHostFingerprint) { this.knownHostFingerprint = knownHostFingerprint; }

    // Transient password (not persisted)
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}
