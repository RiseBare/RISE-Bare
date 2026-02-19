package com.rise.client.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import net.schmizz.sshj.SSHClient;
import net.schmizz.sshj.connection.channel.direct.Session;
import org.apache.commons.io.IOUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * SSH Command Executor for RISE
 * Executes commands on remote servers via SSH
 * V5.9: Fixed timeout handling, JSON via stdin, API version validation
 */
public class SSHCommandExecutor {
    private static final Logger LOG = LoggerFactory.getLogger(SSHCommandExecutor.class);

    private final SSHClient ssh;
    private final ObjectMapper mapper = new ObjectMapper();

    public enum CommandType {
        QUICK(10_000),          // --scan, --status, --check (10s)
        MEDIUM(30_000),        // --start, --stop, --restart (30s)
        UPDATE_CHECK(220_000), // --check with apt-get update (220s)
        UPGRADE(660_000);      // --upgrade (660s = 11min)

        private final int timeoutMs;

        CommandType(int timeoutMs) {
            this.timeoutMs = timeoutMs;
        }

        public int getTimeoutMs() {
            return timeoutMs;
        }
    }

    public SSHCommandExecutor(SSHClient ssh) {
        this.ssh = ssh;
    }

    /**
     * Execute a command and return JSON response
     * V5.9: Fixed timeout handling - join() returns boolean, not throws exception
     */
    public JsonNode executeCommand(String command, CommandType type) throws IOException {
        try (Session session = ssh.startSession()) {
            session.allocateDefaultPTY();

            Session.Command cmd = session.exec(command);

            // V5.9 FIX: join() returns false if timeout, true if completed
            boolean completed = cmd.join(type.getTimeoutMs(), TimeUnit.MILLISECONDS);

            if (!completed) {
                throw new IOException("Command timed out after " +
                    type.getTimeoutMs() / 1000 + "s (no response from server)");
            }

            // Check exit status
            Integer exitStatus = cmd.getExitStatus();
            if (exitStatus == null) {
                throw new IOException("Command completed but exit status unavailable");
            }

            if (exitStatus != 0) {
                String stderr = IOUtils.readFully(cmd.getErrorStream()).toString();
                throw new IOException("Command failed (exit " + exitStatus + "): " + stderr);
            }

            // Parse JSON response
            String stdout = IOUtils.readFully(cmd.getInputStream()).toString();

            try {
                JsonNode result = mapper.readTree(stdout);

                // V5.9: Validate API version in every response
                validateApiVersion(result);

                return result;

            } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
                // Truncate stdout for error message to avoid huge logs
                String preview = stdout.substring(0, Math.min(200, stdout.length()));
                throw new IOException("Invalid JSON response from server: " + preview, e);
            }

        } catch (net.schmizz.sshj.connection.ConnectionException e) {
            throw new IOException("SSH connection lost", e);
        }
    }

    /**
     * Execute command with data sent to stdin
     * V5.9: Secure alternative to echo for JSON transmission
     */
    public JsonNode executeCommandWithStdin(String command, String stdinData,
                                           CommandType type) throws IOException {
        try (Session session = ssh.startSession()) {
            session.allocateDefaultPTY();

            Session.Command cmd = session.exec(command);

            // Send data to stdin
            try (OutputStream stdin = cmd.getOutputStream()) {
                stdin.write(stdinData.getBytes(StandardCharsets.UTF_8));
                stdin.flush();
            }

            // Wait for completion with timeout
            boolean completed = cmd.join(type.getTimeoutMs(), TimeUnit.MILLISECONDS);

            if (!completed) {
                throw new IOException("Command timed out after " +
                    type.getTimeoutMs() / 1000 + "s");
            }

            Integer exitStatus = cmd.getExitStatus();
            if (exitStatus != 0) {
                String stderr = IOUtils.readFully(cmd.getErrorStream()).toString();
                throw new IOException("Command failed (exit " + exitStatus + "): " + stderr);
            }

            String stdout = IOUtils.readFully(cmd.getInputStream()).toString();

            try {
                JsonNode result = mapper.readTree(stdout);
                validateApiVersion(result);
                return result;
            } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
                throw new IOException("Invalid JSON response: " +
                    stdout.substring(0, Math.min(200, stdout.length())), e);
            }

        } catch (net.schmizz.sshj.connection.ConnectionException e) {
            throw new IOException("SSH connection lost", e);
        }
    }

    /**
     * V5.9: Validate API version in every server response
     */
    private void validateApiVersion(JsonNode result) throws IOException {
        if (!result.has("api_version")) {
            throw new IOException("Response missing required field: api_version");
        }

        String serverVersion = result.get("api_version").asText();
        try {
            APIVersionValidator.validateApiVersion(serverVersion);
        } catch (APIVersionException e) {
            throw new IOException("API version mismatch: " + e.getMessage(), e);
        }
    }
}
