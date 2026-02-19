package com.rise.client.ui;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.rise.client.model.DockerContainer;
import com.rise.client.model.PortRule;
import com.rise.client.model.ServerConfig;
import com.rise.client.security.KeyManager;
import com.rise.client.security.KnownHostsManager;
import com.rise.client.service.SSHCommandExecutor;
import com.rise.client.service.SSHConnectionManager;
import javafx.application.Platform;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.concurrent.Task;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.control.Alert;
import javafx.stage.Modality;
import javafx.stage.Stage;
import net.schmizz.sshj.SSHClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Base64;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Main Controller for RISE Client UI
 * Handles onboarding, server management, and all operations
 */
public class MainController {
    private static final Logger LOG = LoggerFactory.getLogger(MainController.class);

    @FXML private ListView<ServerConfig> serverListView;
    @FXML private TabPane mainTabPane;
    @FXML private Tab firewallTab;
    @FXML private Tab dockerTab;
    @FXML private Tab updatesTab;
    @FXML private Tab healthTab;

    // Firewall UI
    @FXML private TableView<PortRule> firewallRulesTable;
    @FXML private TextField portField;
    @FXML private ComboBox<String> protoCombo;
    @FXML private ComboBox<String> actionCombo;
    @FXML private TextField cidrField;
    @FXML private Button addRuleButton;
    @FXML private Button removeRuleButton;
    @FXML private Button scanPortsButton;
    @FXML private Button applyRulesButton;
    @FXML private Button confirmRulesButton;
    @FXML private Button rollbackRulesButton;

    // Docker UI
    @FXML private TableView<DockerContainer> dockerContainerTable;
    @FXML private Button refreshDockerButton;
    @FXML private Button startContainerButton;
    @FXML private Button stopContainerButton;
    @FXML private Button restartContainerButton;

    // Updates UI
    @FXML private Button checkUpdatesButton;
    @FXML private Button upgradeSystemButton;
    @FXML private TextArea updatesOutput;

    // Health UI
    @FXML private Button checkHealthButton;
    @FXML private Label sudoersStatusLabel;
    @FXML private Label sshConfigStatusLabel;
    @FXML private Label nftablesStatusLabel;
    @FXML private Label scriptsStatusLabel;

    // Connection
    private SSHClient currentSsh;
    private SSHCommandExecutor currentExecutor;
    private ServerConfig currentServer;
    private SSHConnectionManager connectionManager;
    private KnownHostsManager knownHostsManager;
    private final ObservableList<ServerConfig> servers = FXCollections.observableArrayList();
    private final ObservableList<PortRule> firewallRules = FXCollections.observableArrayList();
    private final ObservableList<DockerContainer> dockerContainers = FXCollections.observableArrayList();
    private final ObjectMapper mapper = new ObjectMapper();

    private Stage primaryStage;

    @FXML
    public void initialize() {
        LOG.info("Initializing MainController");

        // Initialize combos
        protoCombo.setItems(FXCollections.observableArrayList("tcp", "udp"));
        protoCombo.setValue("tcp");
        actionCombo.setItems(FXCollections.observableArrayList("allow", "drop"));
        actionCombo.setValue("allow");

        // Initialize known hosts manager
        try {
            knownHostsManager = new KnownHostsManager();
            connectionManager = new SSHConnectionManager(knownHostsManager);

            // Set up TOFU callback
            connectionManager.setVerificationCallback((hostname, fingerprint, algorithm) -> {
                return showHostKeyDialog(hostname, fingerprint, algorithm);
            });
        } catch (IOException e) {
            LOG.error("Failed to initialize known hosts manager", e);
        }

        // Load servers
        loadServers();
        serverListView.setItems(servers);

        LOG.info("MainController initialized with {} servers", servers.size());
    }

    public void setStage(Stage stage) {
        this.primaryStage = stage;
    }

    // ==================== Server Management ====================

    private void loadServers() {
        try {
            Path configPath = Paths.get(System.getProperty("user.home"), ".rise", "config.json");
            if (Files.exists(configPath)) {
                JsonNode config = mapper.readTree(configPath.toFile());
                ArrayNode serverArray = (ArrayNode) config.get("servers");
                if (serverArray != null) {
                    for (JsonNode serverNode : serverArray) {
                        ServerConfig server = mapper.treeToValue(serverNode, ServerConfig.class);
                        servers.add(server);
                    }
                }
            }
        } catch (IOException e) {
            LOG.warn("Could not load server config: {}", e.getMessage());
        }
    }

    private void saveServers() {
        try {
            Path configPath = Paths.get(System.getProperty("user.home"), ".rise", "config.json");
            Files.createDirectories(configPath.getParent());

            ObjectNode root = mapper.createObjectNode();
            ArrayNode serverArray = mapper.createArrayNode();

            for (ServerConfig server : servers) {
                serverArray.add(mapper.valueToTree(server));
            }

            root.set("servers", serverArray);
            mapper.writerWithDefaultPrettyPrinter().writeValue(configPath.toFile(), root);

            LOG.info("Saved {} servers to config", servers.size());
        } catch (IOException e) {
            LOG.error("Failed to save servers", e);
            showError("Save Error", "Failed to save server configuration");
        }
    }

    @FXML
    private void onAddServer() {
        showOnboardingDialog();
    }

    @FXML
    private void onRemoveServer() {
        ServerConfig selected = serverListView.getSelectionModel().getSelectedItem();
        if (selected == null) return;

        Alert confirm = new Alert(Alert.AlertType.CONFIRMATION);
        confirm.setTitle("Remove Server");
        confirm.setHeaderText("Remove " + selected.getName() + "?");
        confirm.setContentText("This will delete the SSH key and disconnect from the server.");

        if (confirm.showAndWait().orElse(ButtonType.CANCEL) != ButtonType.CANCEL) {
            // Disconnect
            if (connectionManager != null) {
                connectionManager.disconnect(selected.getId());
            }

            // Delete key
            try {
                KeyManager.deleteKey(selected.getId());
            } catch (IOException e) {
                LOG.warn("Failed to delete key: {}", e.getMessage());
            }

            // Remove from known hosts
            if (knownHostsManager != null) {
                knownHostsManager.removeHost(selected.getHost());
            }

            // Remove from list
            servers.remove(selected);
            saveServers();

            // Clear current server if needed
            if (currentServer != null && currentServer.getId().equals(selected.getId())) {
                currentServer = null;
                currentSsh = null;
                currentExecutor = null;
                mainTabPane.setDisable(true);
            }
        }
    }

    @FXML
    private void onServerSelected() {
        ServerConfig selected = serverListView.getSelectionModel().getSelectedItem();
        if (selected != null) {
            connectToServer(selected);
        }
    }

    private void connectToServer(ServerConfig server) {
        // Close existing connection
        if (currentSsh != null && currentSsh.isConnected()) {
            try { currentSsh.disconnect(); } catch (Exception e) { /* ignore */ }
        }

        showStatus("Connecting to " + server.getName() + "...");

        Task<Void> connectTask = new Task<>() {
            @Override
            protected Void call() throws Exception {
                currentSsh = connectionManager.connectWithKey(server);
                currentExecutor = new SSHCommandExecutor(currentSsh);
                return null;
            }

            @Override
            protected void succeeded() {
                currentServer = server;
                showStatus("Connected to " + server.getName());
                mainTabPane.setDisable(false);
            }

            @Override
            protected void failed() {
                showError("Connection failed", getException());
                mainTabPane.setDisable(true);
            }
        };

        new Thread(connectTask).start();
    }

    /**
     * Show onboarding dialog for adding a new server
     */
    private void showOnboardingDialog() {
        Dialog<ServerConfig> dialog = new Dialog<>();
        dialog.setTitle("Add Server");
        dialog.setHeaderText("Onboard a new server");
        dialog.setGraphic(null);

        // Create form fields
        TextField nameField = new TextField();
        nameField.setPromptText("Server Name");
        nameField.setText("My Server");

        TextField hostField = new TextField();
        hostField.setPromptText("IP or Hostname");

        TextField portField = new TextField();
        portField.setText("22");
        portField.setPromptText("SSH Port");

        TextField otpField = new TextField();
        otpField.setPromptText("OTP from server");

        Label instructionLabel = new Label(
            "1. Run on server: sudo rise-onboard.sh --generate-otp\n" +
            "2. Enter the OTP above\n" +
            "3. Click 'Start Onboarding'"
        );
        instructionLabel.setStyle("-fx-text-fill: #666;");

        // Layout
        GridPane grid = new GridPane();
        grid.setHgap(10);
        grid.setVgap(10);
        grid.setPadding(new javafx.geometry.Insets(20, 10, 10, 10));

        grid.add(new Label("Name:"), 0, 0);
        grid.add(nameField, 1, 0);
        grid.add(new Label("Host:"), 0, 1);
        grid.add(hostField, 1, 1);
        grid.add(new Label("Port:"), 0, 2);
        grid.add(portField, 1, 2);
        grid.add(new Label("OTP:"), 0, 3);
        grid.add(otpField, 1, 3);
        grid.add(instructionLabel, 0, 4, 2, 1);

        dialog.getDialogPane().setContent(grid);
        dialog.getDialogPane().getButtonTypes().addAll(ButtonType.OK, ButtonType.CANCEL);

        // Custom button
        Button startButton = (Button) dialog.getDialogPane().lookupButton(ButtonType.OK);
        startButton.setText("Start Onboarding");

        dialog.setResultConverter(btn -> {
            if (btn == ButtonType.OK) {
                ServerConfig server = new ServerConfig();
                server.setId(UUID.randomUUID().toString());
                server.setName(nameField.getText());
                server.setHost(hostField.getText());
                try {
                    server.setPort(Integer.parseInt(portField.getText()));
                } catch (NumberFormatException e) {
                    server.setPort(22);
                }
                server.setUsername("root"); // For onboarding
                return server;
            }
            return null;
        });

        dialog.showAndWait().ifPresent(server -> {
            String otp = otpField.getText().trim();
            if (otp.isEmpty()) {
                showError("OTP Required", "Please enter the OTP from the server");
                return;
            }
            startOnboarding(server, otp);
        });
    }

    /**
     * Start the onboarding process
     */
    private void startOnboarding(ServerConfig server, String otp) {
        showStatus("Starting onboarding...");

        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                // Step 1: Connect with password (OTP)
                SSHClient ssh = connectionManager.connectWithPassword(server, otp);

                // Step 2: Generate key pair
                KeyManager.KeyPairData keyData = KeyManager.generateKeyPair(server.getId());

                // Step 3: Execute onboard finalize
                SSHCommandExecutor executor = new SSHCommandExecutor(ssh);
                JsonNode result = executor.executeCommand(
                    "sudo /usr/local/bin/rise-onboard.sh --finalize \"" + keyData.publicKeyOpenSSH + "\"",
                    SSHCommandExecutor.CommandType.MEDIUM
                );

                // Step 4: Verify success
                if (!"success".equals(result.get("status").asText())) {
                    throw new IOException("Onboarding failed: " + result.get("message").asText());
                }

                // Step 5: Save key
                KeyManager.savePrivateKey(server.getId(), keyData.privateKeyBytes);

                // Update server config
                server.setUsername("rise-admin");

                // Cleanup
                ssh.disconnect();

                return result;
            }

            @Override
            protected void succeeded() {
                // Add server to list
                servers.add(server);
                saveServers();

                // Connect to the server
                connectToServer(server);

                showStatus("Onboarding completed for " + server.getName());
                showInfo("Success", "Server " + server.getName() + " has been onboarded successfully!");
            }

            @Override
            protected void failed() {
                showError("Onboarding Failed", getException().getMessage());
            }
        };

        new Thread(task).start();
    }

    /**
     * Show dialog to accept new host key (TOFU)
     */
    private boolean showHostKeyDialog(String hostname, String fingerprint, String algorithm) {
        AtomicBoolean result = new AtomicBoolean(false);

        Platform.runLater(() -> {
            Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
            alert.setTitle("New Server Connection");
            alert.setHeaderText("Do you trust this host?");
            alert.setContentText(
                "Hostname: " + hostname + "\n" +
                "Algorithm: " + algorithm + "\n" +
                "Fingerprint: " + fingerprint.substring(0, Math.min(40, fingerprint.length())) + "..."
            );

            ButtonType acceptButton = new ButtonType("Accept & Save");
            ButtonType rejectButton = new ButtonType("Reject");

            alert.getButtonTypes().setAll(acceptButton, rejectButton);

            if (alert.showAndWait().orElse(rejectButton) == acceptButton) {
                result.set(true);
            }
        });

        // Wait for user response (simplified - in real app would be async)
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) { /* ignore */ }

        return result.get();
    }

    // ==================== Firewall Operations ====================

    @FXML
    private void onScanPorts() {
        if (currentExecutor == null) {
            showError("Not connected", "Please connect to a server first");
            return;
        }

        scanPortsButton.setDisable(true);
        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "sudo /usr/local/bin/rise-firewall.sh --scan",
                    SSHCommandExecutor.CommandType.QUICK
                );
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                ArrayNode data = (ArrayNode) result.get("data");

                firewallRules.clear();
                for (JsonNode portNode : data) {
                    PortRule rule = new PortRule(
                        portNode.get("port").asInt(),
                        portNode.get("proto").asText(),
                        "allow",
                        portNode.has("cidr") ? portNode.get("cidr").asText() : null
                    );
                    rule.setStatus(portNode.get("status").asText("unknown"));
                    firewallRules.add(rule);
                }

                showStatus("Scan complete: " + firewallRules.size() + " ports found");
                scanPortsButton.setDisable(false);
            }

            @Override
            protected void failed() {
                showError("Scan failed", getException());
                scanPortsButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    @FXML
    private void onAddRule() {
        try {
            int port = Integer.parseInt(portField.getText());
            String proto = protoCombo.getValue();
            String action = actionCombo.getValue();
            String cidr = cidrField.getText().isEmpty() ? null : cidrField.getText();

            PortRule rule = new PortRule(port, proto, action, cidr);
            firewallRules.add(rule);

            portField.clear();
            cidrField.clear();
        } catch (NumberFormatException e) {
            showError("Invalid port", "Port must be a number between 1 and 65535");
        }
    }

    @FXML
    private void onRemoveRule() {
        PortRule selected = firewallRulesTable.getSelectionModel().getSelectedItem();
        if (selected != null) {
            firewallRules.remove(selected);
        }
    }

    @FXML
    private void onApplyRules() {
        if (currentExecutor == null || firewallRules.isEmpty()) return;

        ArrayNode rulesJson = mapper.createArrayNode();
        for (PortRule rule : firewallRules) {
            ObjectNode ruleObj = mapper.createObjectNode();
            ruleObj.put("port", rule.getPort());
            ruleObj.put("proto", rule.getProto());
            ruleObj.put("action", rule.getAction());
            if (rule.getCidr() != null && !rule.getCidr().isEmpty()) {
                ruleObj.put("cidr", rule.getCidr());
            }
            rulesJson.add(ruleObj);
        }

        String rulesJsonStr;
        try {
            rulesJsonStr = mapper.writeValueAsString(rulesJson);
        } catch (Exception e) {
            showError("Error", "Failed to serialize rules");
            return;
        }

        applyRulesButton.setDisable(true);
        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommandWithStdin(
                    "sudo /usr/local/bin/rise-firewall.sh --apply",
                    rulesJsonStr,
                    SSHCommandExecutor.CommandType.MEDIUM
                );
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                boolean rollbackScheduled = result.get("rollback_scheduled").asBoolean();

                if (!rollbackScheduled) {
                    showWarning("Auto-rollback unavailable.\nManually confirm or rollback within 60s!");
                } else {
                    showStatus("Rules applied. Confirm within 60 seconds to persist.");
                }

                enableConfirmButton();
                applyRulesButton.setDisable(false);
            }

            @Override
            protected void failed() {
                showError("Apply failed", getException());
                applyRulesButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    private void enableConfirmButton() {
        confirmRulesButton.setDisable(false);
        new Thread(() -> {
            try {
                Thread.sleep(60000);
                Platform.runLater(() -> confirmRulesButton.setDisable(true));
            } catch (InterruptedException e) { /* ignore */ }
        }).start();
    }

    @FXML
    private void onConfirmRules() {
        if (currentExecutor == null) return;

        confirmRulesButton.setDisable(true);
        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "sudo /usr/local/bin/rise-firewall.sh --confirm",
                    SSHCommandExecutor.CommandType.QUICK
                );
            }

            @Override
            protected void succeeded() {
                showStatus("Rules confirmed and persisted");
                confirmRulesButton.setDisable(true);
            }

            @Override
            protected void failed() {
                showError("Confirm failed", getException());
                confirmRulesButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    @FXML
    private void onRollbackRules() {
        if (currentExecutor == null) return;

        rollbackRulesButton.setDisable(true);
        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "sudo /usr/local/bin/rise-firewall.sh --rollback",
                    SSHCommandExecutor.CommandType.QUICK
                );
            }

            @Override
            protected void succeeded() {
                showStatus("Rules rolled back");
                rollbackRulesButton.setDisable(false);
            }

            @Override
            protected void failed() {
                showError("Rollback failed", getException());
                rollbackRulesButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    // ==================== Docker Operations ====================

    @FXML
    private void onRefreshDocker() {
        if (currentExecutor == null) return;

        refreshDockerButton.setDisable(true);
        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "sudo /usr/local/bin/rise-docker.sh --list",
                    SSHCommandExecutor.CommandType.QUICK
                );
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                ArrayNode data = (ArrayNode) result.get("data");

                dockerContainers.clear();
                for (JsonNode container : data) {
                    DockerContainer c = new DockerContainer(
                        container.get("id").asText(),
                        container.get("name").asText(),
                        container.get("state").asText(),
                        container.get("image").asText()
                    );
                    dockerContainers.add(c);
                }

                showStatus("Docker: " + dockerContainers.size() + " containers");
                refreshDockerButton.setDisable(false);
            }

            @Override
            protected void failed() {
                showError("Docker list failed", getException());
                refreshDockerButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    @FXML
    private void onStartContainer() { executeContainerAction("start"); }
    @FXML
    private void onStopContainer() { executeContainerAction("stop"); }
    @FXML
    private void onRestartContainer() { executeContainerAction("restart"); }

    private void executeContainerAction(String action) {
        DockerContainer selected = dockerContainerTable.getSelectionModel().getSelectedItem();
        if (selected == null || currentExecutor == null) return;

        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    String.format("sudo /usr/local/bin/rise-docker.sh --%s %s", action, selected.getId()),
                    SSHCommandExecutor.CommandType.MEDIUM
                );
            }

            @Override
            protected void succeeded() {
                showStatus("Container " + action + "ed");
                onRefreshDocker();
            }

            @Override
            protected void failed() {
                showError("Container action failed", getException());
            }
        };

        new Thread(task).start();
    }

    // ==================== Update Operations ====================

    @FXML
    private void onCheckUpdates() {
        if (currentExecutor == null) return;

        checkUpdatesButton.setDisable(true);
        updatesOutput.clear();
        updatesOutput.appendText("Checking for updates...\n");

        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "sudo /usr/local/bin/rise-update.sh --check",
                    SSHCommandExecutor.CommandType.UPDATE_CHECK
                );
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                updatesOutput.appendText(result.get("message").asText() + "\n\n");

                JsonNode summary = result.get("data").get("summary");
                int total = summary.get("total").asInt();
                int security = summary.get("security").asInt();

                updatesOutput.appendText(String.format("Total: %d (Security: %d)\n", total, security));
                checkUpdatesButton.setDisable(false);
            }

            @Override
            protected void failed() {
                updatesOutput.appendText("Check failed: " + getException().getMessage() + "\n");
                checkUpdatesButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    @FXML
    private void onUpgradeSystem() {
        Alert confirm = new Alert(Alert.AlertType.CONFIRMATION);
        confirm.setTitle("Confirm Upgrade");
        confirm.setHeaderText("System Upgrade");
        confirm.setContentText("This will upgrade all packages on the server. Continue?");

        if (confirm.showAndWait().orElse(ButtonType.CANCEL) != ButtonType.OK) return;
        if (currentExecutor == null) return;

        upgradeSystemButton.setDisable(true);
        updatesOutput.appendText("Starting upgrade...\n");

        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "sudo /usr/local/bin/rise-update.sh --upgrade",
                    SSHCommandExecutor.CommandType.UPGRADE
                );
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                updatesOutput.appendText(result.get("message").asText() + "\n");
                upgradeSystemButton.setDisable(false);
            }

            @Override
            protected void failed() {
                updatesOutput.appendText("Upgrade failed: " + getException().getMessage() + "\n");
                upgradeSystemButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    // ==================== Health Check ====================

    @FXML
    private void onCheckHealth() {
        if (currentExecutor == null) return;

        checkHealthButton.setDisable(true);
        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                return currentExecutor.executeCommand(
                    "/usr/local/bin/rise-health.sh",
                    SSHCommandExecutor.CommandType.QUICK
                );
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                JsonNode checks = result.get("checks");

                updateHealthIndicator(sudoersStatusLabel, checks.get("sudoers_file").asText());
                updateHealthIndicator(sshConfigStatusLabel, checks.get("ssh_dropin_clean").asText());
                updateHealthIndicator(nftablesStatusLabel, checks.get("nftables_include").asText());
                updateHealthIndicator(scriptsStatusLabel, checks.get("scripts_present").asText());

                int failures = 0;
                var values = checks.elements();
                while (values.hasNext()) {
                    if ("fail".equals(values.next().asText())) failures++;
                }

                if (failures > 0) {
                    showWarning(failures + " health check(s) failed");
                } else {
                    showStatus("All health checks passed");
                }

                checkHealthButton.setDisable(false);
            }

            @Override
            protected void failed() {
                showError("Health check failed", getException());
                checkHealthButton.setDisable(false);
            }
        };

        new Thread(task).start();
    }

    private void updateHealthIndicator(Label label, String status) {
        label.setText(status.toUpperCase());
        label.setStyle("-fx-text-fill: " + ("pass".equals(status) ? "green;" : "red;"));
    }

    // ==================== Helpers ====================

    private void showStatus(String message) {
        LOG.info(message);
    }

    private void showError(String title, String message) {
        Platform.runLater(() -> {
            Alert alert = new Alert(Alert.AlertType.ERROR);
            alert.setTitle(title);
            alert.setHeaderText(message);
            alert.showAndWait();
        });
    }

    private void showError(String title, Exception e) {
        showError(title, e.getMessage());
    }

    private void showWarning(String message) {
        Platform.runLater(() -> {
            Alert alert = new Alert(Alert.AlertType.WARNING);
            alert.setTitle("Warning");
            alert.setHeaderText(message);
            alert.showAndWait();
        });
    }

    private void showInfo(String title, String message) {
        Platform.runLater(() -> {
            Alert alert = new Alert(Alert.AlertType.INFORMATION);
            alert.setTitle(title);
            alert.setHeaderText(message);
            alert.showAndWait();
        });
    }

    // Simple Docker container model
    public static class DockerContainer {
        private final String id, name, state, image;

        public DockerContainer(String id, String name, String state, String image) {
            this.id = id;
            this.name = name;
            this.state = state;
            this.image = image;
        }

        public String getId() { return id; }
        public String getName() { return name; }
        public String getState() { return state; }
        public String getImage() { return image; }
    }
}
