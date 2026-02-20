package com.rise.client.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import net.schmizz.sshj.SSHClient;
import net.schmizz.sshj.connection.channel.direct.Session;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Callable;

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
     * Read stream to string
     */
    private String readStream(java.io.InputStream inputStream) throws IOException {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append("\n");
            }
        }
        return sb.toString();
    }

    /**
     * Execute a command and return JSON response with timeout
     */
    public JsonNode executeCommand(String command, CommandType type) throws IOException {
        final Session.Command[] cmdHolder = new Session.Command[1];

        Callable<JsonNode> task = () -> {
            try (Session session = ssh.startSession()) {
                session.allocateDefaultPTY();

                Session.Command cmd = session.exec(command);
                cmdHolder[0] = cmd;

                // Wait for command completion
                cmd.join(type.getTimeoutMs(), TimeUnit.MILLISECONDS);

                // Check exit status
                Integer exitStatus = cmd.getExitStatus();
                if (exitStatus == null) {
                    throw new IOException("Command completed but exit status unavailable");
                }

                if (exitStatus != 0) {
                    String stderr = readStream(cmd.getErrorStream());
                    throw new IOException("Command failed (exit " + exitStatus + "): " + stderr);
                }

                // Parse JSON response
                String stdout = readStream(cmd.getInputStream());

                try {
                    JsonNode result = mapper.readTree(stdout);
                    validateApiVersion(result);
                    return result;
                } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
                    String preview = stdout.substring(0, Math.min(200, stdout.length()));
                    throw new IOException("Invalid JSON response from server: " + preview, e);
                }
            }
        };

        try {
            var executor = Executors.newSingleThreadExecutor();
            Future<JsonNode> future = executor.submit(task);
            JsonNode result = future.get(type.getTimeoutMs(), TimeUnit.MILLISECONDS);
            executor.shutdown();
            return result;
        } catch (TimeoutException e) {
            if (cmdHolder[0] != null) {
                try { cmdHolder[0].close(); } catch (Exception ignored) {}
            }
            throw new IOException("Command timed out after " + type.getTimeoutMs() / 1000 + "s");
        } catch (java.util.concurrent.ExecutionException e) {
            throw new IOException("Command execution failed: " + e.getCause().getMessage(), e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("Command interrupted", e);
        }
    }

    /**
     * Execute command with data sent to stdin
     */
    public JsonNode executeCommandWithStdin(String command, String stdinData,
                                           CommandType type) throws IOException {
        final Session.Command[] cmdHolder = new Session.Command[1];

        Callable<JsonNode> task = () -> {
            try (Session session = ssh.startSession()) {
                session.allocateDefaultPTY();

                Session.Command cmd = session.exec(command);
                cmdHolder[0] = cmd;

                // Send data to stdin
                try (OutputStream stdin = cmd.getOutputStream()) {
                    stdin.write(stdinData.getBytes(StandardCharsets.UTF_8));
                    stdin.flush();
                }

                // Wait for completion with timeout
                cmd.join(type.getTimeoutMs(), TimeUnit.MILLISECONDS);

                Integer exitStatus = cmd.getExitStatus();
                if (exitStatus != 0) {
                    String stderr = readStream(cmd.getErrorStream());
                    throw new IOException("Command failed (exit " + exitStatus + "): " + stderr);
                }

                String stdout = readStream(cmd.getInputStream());

                try {
                    JsonNode result = mapper.readTree(stdout);
                    validateApiVersion(result);
                    return result;
                } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
                    throw new IOException("Invalid JSON response: " +
                        stdout.substring(0, Math.min(200, stdout.length())), e);
                }
            }
        };

        try {
            var executor = Executors.newSingleThreadExecutor();
            Future<JsonNode> future = executor.submit(task);
            JsonNode result = future.get(type.getTimeoutMs(), TimeUnit.MILLISECONDS);
            executor.shutdown();
            return result;
        } catch (TimeoutException e) {
            if (cmdHolder[0] != null) {
                try { cmdHolder[0].close(); } catch (Exception ignored) {}
            }
            throw new IOException("Command timed out after " + type.getTimeoutMs() / 1000 + "s");
        } catch (java.util.concurrent.ExecutionException e) {
            throw new IOException("Command execution failed: " + e.getCause().getMessage(), e.getCause());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException("Command interrupted", e);
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
