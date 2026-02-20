package com.rise.client.ui;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.rise.client.model.PortRule;
import com.rise.client.model.ServerConfig;
import com.rise.client.security.KeyManager;
import com.rise.client.security.KnownHostsManager;
import com.rise.client.service.SSHCommandExecutor;
import com.rise.client.service.SSHConnectionManager;
import com.rise.client.i18n.Messages;
import com.rise.client.config.AppSettings;
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
import javafx.scene.layout.GridPane;
import javafx.scene.layout.VBox;
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

    /**
     * SSH Security mode for onboarding
     */
    public enum SecurityMode {
        MODE_1("Mode 1: Keep password access for all users",
               "Non recommandé. Tous les utilisateurs peuvent se connecter par mot de passe.\n" +
               "Risque d'attaques par force brute. À utiliser uniquement en test."),
        MODE_2("Mode 2: Root only with SSH key, others can use password",
               "Transition. Le compte root/sudo uniquement par clé SSH.\n" +
               "Les autres utilisateurs conservent le mot de passe."),
        MODE_3("Mode 3: SSH key only for all users (RECOMMENDED)",
               "Recommandé pour production. Toutes les connexions SSH nécessitent une clé.\n" +
               "Plus de risque de mot de passe compromis.");

        private final String title;
        private final String description;

        SecurityMode(String title, String description) {
            this.title = title;
            this.description = description;
        }

        public String getTitle() { return title; }
        public String getDescription() { return description; }
    }

    @FXML private ListView<ServerConfig> serverListView;
    @FXML private TabPane mainTabPane;
    @FXML private Tab firewallTab;
    @FXML private Tab dockerTab;
    @FXML private Tab updatesTab;
    @FXML private Tab healthTab;

    // Firewall UI
    @FXML private Label firewallTitleLabel;
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
    @FXML private Label dockerTitleLabel;
    @FXML private TableView<DockerContainer> dockerContainerTable;
    @FXML private Button refreshDockerButton;
    @FXML private Button startContainerButton;
    @FXML private Button stopContainerButton;
    @FXML private Button restartContainerButton;

    // Updates UI
    @FXML private Label updatesTitleLabel;
    @FXML private Button checkUpdatesButton;
    @FXML private Button upgradeSystemButton;
    @FXML private TextArea updatesOutput;

    // Health UI
    @FXML private Label healthTitleLabel;
    @FXML private Button checkHealthButton;
    @FXML private Label sudoersStatusLabel;
    @FXML private Label sshConfigStatusLabel;
    @FXML private Label nftablesStatusLabel;
    @FXML private Label scriptsStatusLabel;

    // Header & Status
    @FXML private Label headerLabel;
    @FXML private Button settingsButton;
    @FXML private Label serversLabel;
    @FXML private Button addServerButton;
    @FXML private Button removeServerButton;
    @FXML private Label statusLabel;

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

    /**
     * Load all UI texts from Messages (i18n)
     */
    private void loadI18nTexts() {
        Messages msg = Messages.getInstance();

        // Header
        if (headerLabel != null) headerLabel.setText(msg.get("app.title"));
        if (settingsButton != null) settingsButton.setText(msg.get("menu.settings"));
        if (serversLabel != null) serversLabel.setText(msg.get("server.list") + ":");
        if (addServerButton != null) addServerButton.setText(msg.get("server.add"));
        if (removeServerButton != null) removeServerButton.setText(msg.get("server.remove"));

        // Tabs
        if (firewallTab != null) firewallTab.setText(msg.get("tab.firewall"));
        if (dockerTab != null) dockerTab.setText(msg.get("tab.docker"));
        if (updatesTab != null) updatesTab.setText(msg.get("tab.updates"));
        if (healthTab != null) healthTab.setText(msg.get("tab.health"));

        // Firewall
        if (firewallTitleLabel != null) firewallTitleLabel.setText(msg.get("firewall.title"));
        if (scanPortsButton != null) scanPortsButton.setText(msg.get("firewall.rules"));
        if (applyRulesButton != null) applyRulesButton.setText(msg.get("firewall.apply"));
        if (rollbackRulesButton != null) rollbackRulesButton.setText(msg.get("firewall.rollback"));
        if (addRuleButton != null) addRuleButton.setText(msg.get("firewall.addRule"));
        if (removeRuleButton != null) removeRuleButton.setText(msg.get("firewall.removeRule"));

        // Docker
        if (dockerTitleLabel != null) dockerTitleLabel.setText(msg.get("docker.title"));
        if (refreshDockerButton != null) refreshDockerButton.setText(msg.get("tooltip.refresh"));
        if (startContainerButton != null) startContainerButton.setText(msg.get("docker.start"));
        if (stopContainerButton != null) stopContainerButton.setText(msg.get("docker.stop"));
        if (restartContainerButton != null) restartContainerButton.setText(msg.get("docker.restart"));

        // Updates
        if (updatesTitleLabel != null) updatesTitleLabel.setText(msg.get("updates.title"));
        if (checkUpdatesButton != null) checkUpdatesButton.setText(msg.get("updates.check"));
        if (upgradeSystemButton != null) upgradeSystemButton.setText(msg.get("updates.install"));

        // Health
        if (healthTitleLabel != null) healthTitleLabel.setText(msg.get("health.title"));
        if (checkHealthButton != null) checkHealthButton.setText(msg.get("health.run"));

        // Status
        if (statusLabel != null) statusLabel.setText(msg.get("status.connecting"));
    }

    @FXML
    public void initialize() {
        LOG.info("Initializing MainController");

        // Load i18n texts
        loadI18nTexts();

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

    /**
     * Open settings dialog
     */
    @FXML
    private void onOpenSettings() {
        Messages msg = Messages.getInstance();
        AppSettings settings = AppSettings.getInstance();

        Dialog<ButtonType> dialog = new Dialog<>();
        dialog.setTitle(msg.get("settings.title"));
        dialog.setGraphic(null);

        GridPane grid = new GridPane();
        grid.setHgap(10);
        grid.setVgap(10);
        grid.setPadding(new javafx.geometry.Insets(20, 10, 10, 10));

        // Language selection
        Label langLabel = new Label(msg.get("settings.language") + ":");
        ComboBox<String> langCombo = new ComboBox<>();
        for (String lang : Messages.getAvailableLanguages()) {
            langCombo.getItems().add(Messages.getLanguageName(lang));
        }
        langCombo.setValue(Messages.getLanguageName(settings.getLanguage()));

        // Auto update checkbox
        CheckBox autoUpdateCheck = new CheckBox(msg.get("settings.autoUpdate"));
        autoUpdateCheck.setSelected(settings.isAutoUpdateScripts());

        grid.add(langLabel, 0, 0);
        grid.add(langCombo, 1, 0);
        grid.add(autoUpdateCheck, 0, 1, 2, 1);

        dialog.getDialogPane().setContent(grid);
        dialog.getDialogPane().getButtonTypes().addAll(ButtonType.OK, ButtonType.CANCEL);

        dialog.showAndWait().ifPresent(result -> {
            if (result == ButtonType.OK) {
                // Save settings
                int selectedIndex = langCombo.getSelectionModel().getSelectedIndex();
                String newLang = Messages.getAvailableLanguages().get(selectedIndex);
                settings.setLanguage(newLang);
                settings.setAutoUpdateScripts(autoUpdateCheck.isSelected());
                settings.save();

                // Reload UI texts
                loadI18nTexts();
                primaryStage.setTitle(msg.get("app.title"));

                showInfo(msg.get("dialog.success"), msg.get("settings.saved"));
            }
        });
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

        TextField usernameField = new TextField();
        usernameField.setText("root");
        usernameField.setPromptText("Username (root or sudo user)");

        TextField passwordField = new PasswordField();
        passwordField.setPromptText("Password");

        Messages msg = Messages.getInstance();

        Label instructionLabel = new Label(
            msg.get("onboarding.instruction")
        );
        instructionLabel.setStyle("-fx-text-fill: #666;");

        // Security mode selection
        Label securityLabel = new Label(msg.get("onboarding.securityMode") + ":");
        securityLabel.setStyle("-fx-font-weight: bold;");

        ToggleGroup securityGroup = new ToggleGroup();
        RadioButton mode1 = new RadioButton(SecurityMode.MODE_1.getTitle());
        mode1.setToggleGroup(securityGroup);
        mode1.setUserData(SecurityMode.MODE_1);
        mode1.setStyle("-fx-padding: 5;");

        RadioButton mode2 = new RadioButton(SecurityMode.MODE_2.getTitle());
        mode2.setToggleGroup(securityGroup);
        mode2.setStyle("-fx-padding: 5;");

        RadioButton mode3 = new RadioButton(SecurityMode.MODE_3.getTitle());
        mode3.setToggleGroup(securityGroup);
        mode3.setUserData(SecurityMode.MODE_3);
        mode3.setStyle("-fx-padding: 5;");
        mode3.setSelected(true); // Default to recommended

        Label securityDescLabel = new Label(SecurityMode.MODE_3.getDescription());
        securityDescLabel.setStyle("-fx-text-fill: #666; -fx-font-size: 11;");
        securityDescLabel.setWrapText(true);

        // Update description when selection changes
        securityGroup.selectedToggleProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal != null) {
                SecurityMode mode = (SecurityMode) newVal.getUserData();
                securityDescLabel.setText(mode.getDescription());
            }
        });

        // Layout
        GridPane grid = new GridPane();
        grid.setHgap(10);
        grid.setVgap(10);
        grid.setPadding(new javafx.geometry.Insets(20, 10, 10, 10));

        grid.add(new Label(msg.get("onboarding.name") + ":"), 0, 0);
        grid.add(nameField, 1, 0);
        grid.add(new Label(msg.get("onboarding.host") + ":"), 0, 1);
        grid.add(hostField, 1, 1);
        grid.add(new Label(msg.get("onboarding.port") + ":"), 0, 2);
        grid.add(portField, 1, 2);
        grid.add(new Label(msg.get("onboarding.username") + ":"), 0, 3);
        grid.add(usernameField, 1, 3);
        grid.add(new Label(msg.get("onboarding.password") + ":"), 0, 4);
        grid.add(passwordField, 1, 4);
        grid.add(instructionLabel, 0, 5, 2, 1);
        grid.add(securityLabel, 0, 6, 2, 1);
        grid.add(mode1, 0, 7, 2, 1);
        grid.add(mode2, 0, 8, 2, 1);
        grid.add(mode3, 0, 9, 2, 1);
        grid.add(securityDescLabel, 0, 10, 2, 1);

        dialog.getDialogPane().setContent(grid);
        dialog.getDialogPane().setPrefWidth(500);
        dialog.getDialogPane().getButtonTypes().addAll(ButtonType.OK, ButtonType.CANCEL);

        // Custom button
        Button startButton = (Button) dialog.getDialogPane().lookupButton(ButtonType.OK);
        startButton.setText(msg.get("onboarding.addButton"));

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
                server.setUsername(usernameField.getText());
                server.setPassword(passwordField.getText());

                // Get selected security mode
                Toggle selected = securityGroup.getSelectedToggle();
                if (selected != null) {
                    server.setSecurityMode(((SecurityMode) selected.getUserData()).name());
                } else {
                    server.setSecurityMode(SecurityMode.MODE_3.name());
                }

                return server;
            }
            return null;
        });

        dialog.showAndWait().ifPresent(server -> {
            String password = server.getPassword();
            if (password == null || password.isEmpty()) {
                showError(msg.get("dialog.error"), msg.get("error.passwordRequired"));
                return;
            }
            startOnboarding(server);
        });
    }

    /**
     * Start the onboarding process
     */
    private void startOnboarding(ServerConfig server) {
        showStatus("Starting onboarding...");

        Task<JsonNode> task = new Task<>() {
            @Override
            protected JsonNode call() throws Exception {
                // Step 1: Connect with password (initial connection)
                SSHClient ssh = connectionManager.connectWithPassword(server, server.getPassword());

                // Step 2: Check if RISE is already installed
                SSHCommandExecutor executor = new SSHCommandExecutor(ssh);
                JsonNode checkResult = executor.executeCommand(
                    "sudo /usr/local/bin/rise-onboard.sh --check",
                    SSHCommandExecutor.CommandType.QUICK
                );

                boolean riseInstalled = checkResult.has("rise_installed") && checkResult.get("rise_installed").asBoolean();
                boolean keyAlreadyRegistered = false;

                // Step 3: Generate key pair for this device
                KeyManager.KeyPairData keyData = KeyManager.generateKeyPair(server.getId());

                JsonNode result;

                if (riseInstalled) {
                    // RISE already installed - just add this device's key
                    showStatus("RISE detected, adding this device...");

                    result = executor.executeCommand(
                        "sudo /usr/local/bin/rise-onboard.sh --add-device \"" + keyData.publicKeyOpenSSH + "\"",
                        SSHCommandExecutor.CommandType.MEDIUM
                    );

                    if (result.has("already_exists") && result.get("already_exists").asBoolean()) {
                        keyAlreadyRegistered = true;
                        LOG.info("This device's key was already registered");
                    }
                } else {
                    // Fresh installation - run full onboarding
                    showStatus("Installing RISE on new server...");

                    // Run setup-env.sh first
                    try {
                        executor.executeCommand(
                            "sudo /usr/local/bin/setup-env.sh --install",
                            SSHCommandExecutor.CommandType.MEDIUM
                        );
                    } catch (Exception e) {
                        LOG.warn("setup-env.sh --install failed, trying direct execution: " + e.getMessage());
                        // Try alternative: execute setup script from remote
                        executor.executeCommand(
                            "curl -s https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/scripts/setup-env.sh | sudo bash -s -- --install",
                            SSHCommandExecutor.CommandType.MEDIUM
                        );
                    }

                    // Generate OTP for finalization
                    JsonNode otpResult = executor.executeCommand(
                        "sudo /usr/local/bin/rise-onboard.sh --generate-otp",
                        SSHCommandExecutor.CommandType.QUICK
                    );

                    // Apply security mode
                    String securityMode = server.getSecurityMode() != null ? server.getSecurityMode() : "MODE_3";
                    applySecurityMode(ssh, securityMode);

                    // Finalize onboarding
                    result = executor.executeCommand(
                        "sudo /usr/local/bin/rise-onboard.sh --finalize \"" + keyData.publicKeyOpenSSH + "\"",
                        SSHCommandExecutor.CommandType.MEDIUM
                    );
                }

                // Verify success
                if (!"success".equals(result.get("status").asText())) {
                    throw new IOException("Onboarding failed: " + result.get("message").asText());
                }

                // Step 4: Save key
                KeyManager.savePrivateKey(server.getId(), keyData.privateKeyBytes);

                // Update server config
                server.setUsername("rise-admin");
                server.setPassword(null); // Clear password

                // Cleanup
                ssh.disconnect();

                // Return result info
                ObjectMapper mapper = new ObjectMapper();
                ObjectNode resultInfo = mapper.createObjectNode();
                resultInfo.put("status", "success");
                resultInfo.put("rise_installed", riseInstalled);
                resultInfo.put("key_already_registered", keyAlreadyRegistered);

                return resultInfo;
            }

            @Override
            protected void succeeded() {
                JsonNode result = getValue();
                boolean wasAlreadyInstalled = result.has("rise_installed") && result.get("rise_installed").asBoolean();
                boolean keyAlreadyRegistered = result.has("key_already_registered") && result.get("key_already_registered").asBoolean();

                // Add server to list
                servers.add(server);
                saveServers();

                // Connect to the server
                connectToServer(server);

                if (keyAlreadyRegistered) {
                    showStatus("Connexion établie (clé déjà enregistrée)");
                } else if (wasAlreadyInstalled) {
                    showStatus("Appareil ajouté au serveur RISE existant");
                } else {
                    showStatus("Nouveau serveur RISE configuré");
                }

                String message;
                if (keyAlreadyRegistered) {
                    message = "Connexion réussie ! Cette appareil était déjà enregistré.";
                } else if (wasAlreadyInstalled) {
                    message = "Serveur mis à jour : cet appareil a été ajouté.\n\n" +
                              "Documentation des modes de sécurité :\n" +
                              "https://github.com/RiseBare/RISE-Bare/blob/main/docs/SECURITY_MODES.md";
                } else {
                    message = "Serveur " + server.getName() + " a été configuré avec succès !\n\n" +
                              "Le compte 'rise-admin' est accessible uniquement par clé SSH.\n\n" +
                              "Documentation :\n" +
                              "https://github.com/RiseBare/RISE-Bare/blob/main/docs/SECURITY_MODES.md";
                }

                showInfo("Succès", message);
            }

            @Override
            protected void failed() {
                showError("Échec de l'onboarding", getException().getMessage());
            }
        };

        new Thread(task).start();
    }

    /**
     * Apply security mode to SSH configuration
     */
    private void applySecurityMode(SSHClient ssh, String securityMode) throws IOException {
        SSHCommandExecutor executor = new SSHCommandExecutor(ssh);

        String sshdConfig;
        String passwordAuth;

        switch (securityMode) {
            case "MODE_1":
                // Keep password authentication
                passwordAuth = "yes";
                break;
            case "MODE_2":
                // Root only with key, others can use password
                passwordAuth = "yes";
                // Note: PermitRootLogin is handled separately
                break;
            case "MODE_3":
            default:
                // SSH key only for all
                passwordAuth = "no";
                break;
        }

        // Configure SSH to restrict password auth based on mode
        String config = "PasswordAuthentication " + passwordAuth + "\n" +
                       "PermitRootLogin prohibit-password\n";

        // Write config
        executor.executeCommand(
            "echo '" + config + "' | sudo tee /etc/ssh/sshd_config.d/99-rise-security.conf > /dev/null && " +
            "sudo systemctl reload sshd",
            SSHCommandExecutor.CommandType.QUICK
        );

        LOG.info("Security mode applied: " + securityMode);
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

    private void showError(String title, Throwable t) {
        showError(title, t.getMessage());
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
