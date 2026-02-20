package com.rise.client.i18n;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;

/**
 * Internationalization (i18n) support for RISE Client
 * Loads messages from GitHub repository, with local caching
 */
public class Messages {

    private static final Logger LOG = LoggerFactory.getLogger(Messages.class);

    private static final String DEFAULT_LANGUAGE = "en";
    private static final String GITHUB_BASE_URL = "https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/i18n/";
    private static final String CACHE_DIR = System.getProperty("user.home") + "/.rise/i18n/";

    private static Messages instance;

    private String currentLanguage;
    private Map<String, String> messages;
    private String loadedVersion;

    private Messages() {
        messages = new HashMap<>();
        ensureCacheDir();
        loadMessages(DEFAULT_LANGUAGE);
    }

    public static synchronized Messages getInstance() {
        if (instance == null) {
            instance = new Messages();
        }
        return instance;
    }

    private void ensureCacheDir() {
        try {
            Files.createDirectories(Paths.get(CACHE_DIR));
        } catch (IOException e) {
            LOG.warn("Failed to create i18n cache directory", e);
        }
    }

    /**
     * Get available languages (ISO 639-1 codes)
     */
    public static List<String> getAvailableLanguages() {
        return Arrays.asList("en", "fr", "th", "zh", "de", "es", "ja", "ko", "pt", "ru");
    }

    /**
     * Get language display name
     */
    public static String getLanguageName(String code) {
        switch (code) {
            case "en": return "English (US)";
            case "fr": return "Français";
            case "th": return "ไทย";
            case "zh": return "中文";
            case "de": return "Deutsch";
            case "es": return "Español";
            case "ja": return "日本語";
            case "ko": return "한국어";
            case "pt": return "Português";
            case "ru": return "Русский";
            default: return code;
        }
    }

    /**
     * Set current language and load messages
     */
    public void setLanguage(String languageCode) {
        if (getAvailableLanguages().contains(languageCode)) {
            this.currentLanguage = languageCode;
            loadMessages(languageCode);
        } else {
            this.currentLanguage = DEFAULT_LANGUAGE;
            loadMessages(DEFAULT_LANGUAGE);
        }
    }

    public String getCurrentLanguage() {
        return currentLanguage;
    }

    /**
     * Load messages - tries GitHub first, falls back to cache, then built-in
     */
    private void loadMessages(String languageCode) {
        messages.clear();
        loadedVersion = null;

        // Try GitHub first
        if (loadFromGitHub(languageCode)) {
            return;
        }

        // Try local cache
        if (loadFromCache(languageCode)) {
            return;
        }

        // Fallback to built-in
        loadBuiltInMessages(languageCode);
    }

    /**
     * Load messages from GitHub
     */
    private boolean loadFromGitHub(String languageCode) {
        String url = GITHUB_BASE_URL + languageCode + ".json";
        String versionUrl = GITHUB_BASE_URL + "version.json";

        try {
            // Check version first
            String latestVersion = fetchUrl(versionUrl);
            if (latestVersion != null && latestVersion.equals(loadedVersion)) {
                LOG.info("Language file version unchanged, skipping download");
                return messages.size() > 0;
            }

            // Download messages
            String content = fetchUrl(url);
            if (content != null && parseMessages(content)) {
                // Save to cache
                saveToCache(languageCode, content, latestVersion);
                loadedVersion = latestVersion;
                LOG.info("Loaded messages from GitHub for language: " + languageCode);
                return true;
            }
        } catch (Exception e) {
            LOG.debug("Failed to load from GitHub: " + e.getMessage());
        }
        return false;
    }

    /**
     * Fetch URL content
     */
    private String fetchUrl(String urlStr) {
        try {
            URL url = new URL(urlStr);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(5000);
            conn.setReadTimeout(5000);
            conn.setRequestProperty("User-Agent", "RISE-Client/1.0");

            int responseCode = conn.getResponseCode();
            if (responseCode == 200) {
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = reader.readLine()) != null) {
                        sb.append(line).append("\n");
                    }
                    return sb.toString();
                }
            }
            conn.disconnect();
        } catch (Exception e) {
            LOG.debug("Fetch failed for " + urlStr + ": " + e.getMessage());
        }
        return null;
    }

    /**
     * Parse JSON messages
     */
    private boolean parseMessages(String content) {
        try {
            // Simple JSON parsing (key: "value")
            // More robust parsing could use Jackson, but we want minimal dependencies
            messages.clear();

            String[] lines = content.split("\n");
            for (String line : lines) {
                line = line.trim();
                if (line.startsWith("\"") && line.contains(":")) {
                    int colonPos = line.indexOf(":");
                    String key = line.substring(1, colonPos - 1).trim();
                    String rest = line.substring(colonPos + 1).trim();

                    // Handle value
                    if (rest.startsWith("\"") && rest.endsWith("\",")) {
                        String value = rest.substring(1, rest.length() - 2);
                        value = value.replace("\\\"", "\"");
                        value = value.replace("\\n", "\n");
                        messages.put(key, value);
                    } else if (rest.startsWith("\"")) {
                        String value = rest.substring(1);
                        if (value.endsWith("\"")) {
                            value = value.substring(0, value.length() - 1);
                        }
                        value = value.replace("\\\"", "\"");
                        value = value.replace("\\n", "\n");
                        messages.put(key, value);
                    }
                }
            }
            return messages.size() > 0;
        } catch (Exception e) {
            LOG.warn("Failed to parse messages: " + e.getMessage());
            return false;
        }
    }

    /**
     * Save messages to local cache
     */
    private void saveToCache(String languageCode, String content, String version) {
        try {
            Path cacheFile = Paths.get(CACHE_DIR + languageCode + ".json");
            Files.write(cacheFile, content.getBytes(StandardCharsets.UTF_8));

            if (version != null) {
                Path versionFile = Paths.get(CACHE_DIR + languageCode + ".version");
                Files.write(versionFile, version.getBytes(StandardCharsets.UTF_8));
            }
        } catch (IOException e) {
            LOG.warn("Failed to save to cache: " + e.getMessage());
        }
    }

    /**
     * Load messages from local cache
     */
    private boolean loadFromCache(String languageCode) {
        try {
            Path cacheFile = Paths.get(CACHE_DIR + languageCode + ".json");
            if (Files.exists(cacheFile)) {
                String content = Files.readString(cacheFile);
                if (parseMessages(content)) {
                    // Check version
                    Path versionFile = Paths.get(CACHE_DIR + languageCode + ".version");
                    if (Files.exists(versionFile)) {
                        loadedVersion = Files.readString(versionFile).trim();
                    }
                    LOG.info("Loaded messages from cache for language: " + languageCode);
                    return true;
                }
            }
        } catch (Exception e) {
            LOG.debug("Failed to load from cache: " + e.getMessage());
        }
        return false;
    }

    /**
     * Load built-in fallback messages
     */
    private void loadBuiltInMessages(String languageCode) {
        messages.clear();

        switch (languageCode) {
            case "fr":
                loadFrenchMessages();
                break;
            default:
                loadEnglishMessages();
                break;
        }
        LOG.info("Loaded built-in messages for language: " + languageCode);
    }

    private void loadEnglishMessages() {
        messages.put("app.title", "RISE - Remote Infrastructure Security & Efficiency");
        messages.put("app.version", "Version");

        messages.put("menu.file", "File");
        messages.put("menu.addServer", "Add Server");
        messages.put("menu.settings", "Settings");
        messages.put("menu.exit", "Exit");
        messages.put("menu.help", "Help");
        messages.put("menu.about", "About");

        messages.put("server.list", "Servers");
        messages.put("server.add", "Add Server");
        messages.put("server.remove", "Remove");
        messages.put("server.connect", "Connect");
        messages.put("server.disconnect", "Disconnect");
        messages.put("server.noServers", "No servers configured. Click 'Add Server' to begin.");

        messages.put("tab.firewall", "Firewall");
        messages.put("tab.docker", "Docker");
        messages.put("tab.updates", "Updates");
        messages.put("tab.health", "Health");

        messages.put("onboarding.title", "Add Server");
        messages.put("onboarding.header", "Onboard a new server");
        messages.put("onboarding.name", "Name");
        messages.put("onboarding.host", "Host");
        messages.put("onboarding.port", "Port");
        messages.put("onboarding.username", "Username");
        messages.put("onboarding.password", "Password");
        messages.put("onboarding.securityMode", "SSH Security Mode");
        messages.put("onboarding.instruction", "Enter server credentials. If RISE is already installed, this device's SSH key will be added automatically.");
        messages.put("onboarding.addButton", "Add Server");

        messages.put("security.mode1", "Mode 1: Keep password access for all users");
        messages.put("security.mode1.desc", "Not recommended. All users can connect by password. Risk of brute force attacks. Use only for testing.");
        messages.put("security.mode2", "Mode 2: Root only with SSH key, others can use password");
        messages.put("security.mode2.desc", "Transition mode. Root/sudo account SSH key only. Other users keep password access.");
        messages.put("security.mode3", "Mode 3: SSH key only for all users (RECOMMENDED)");
        messages.put("security.mode3.desc", "Recommended for production. All SSH connections require a key. No risk of compromised passwords.");

        messages.put("status.connecting", "Connecting...");
        messages.put("status.connected", "Connected");
        messages.put("status.disconnected", "Disconnected");
        messages.put("status.onboarding", "Starting onboarding...");
        messages.put("status.checkingRISE", "Checking RISE installation...");
        messages.put("status.riseDetected", "RISE detected, adding this device...");
        messages.put("status.installingRISE", "Installing RISE on new server...");
        messages.put("status.success", "Operation completed successfully");

        messages.put("dialog.success", "Success");
        messages.put("dialog.error", "Error");
        messages.put("dialog.warning", "Warning");
        messages.put("dialog.confirm", "Confirm");
        messages.put("dialog.cancel", "Cancel");
        messages.put("dialog.ok", "OK");
        messages.put("dialog.yes", "Yes");
        messages.put("dialog.no", "No");

        messages.put("onboarding.success.new", "Server %s has been configured successfully!");
        messages.put("onboarding.success.existing", "Server updated: this device has been added.");
        messages.put("onboarding.success.alreadyRegistered", "Connection successful! This device was already registered.");
        messages.put("onboarding.error", "Onboarding failed: %s");

        messages.put("settings.title", "Settings");
        messages.put("settings.language", "Language");
        messages.put("settings.theme", "Theme");
        messages.put("settings.autoUpdate", "Auto-update scripts on connect");
        messages.put("settings.save", "Save");
        messages.put("settings.saved", "Settings saved");

        messages.put("error.passwordRequired", "Password is required");
        messages.put("error.connectionFailed", "Connection failed: %s");
        messages.put("error.invalidCredentials", "Invalid credentials");
        messages.put("error.sshKeyRequired", "SSH key required");

        messages.put("firewall.title", "Firewall Management");
        messages.put("firewall.rules", "Rules");
        messages.put("firewall.addRule", "Add Rule");
        messages.put("firewall.removeRule", "Remove");
        messages.put("firewall.apply", "Apply");
        messages.put("firewall.rollback", "Rollback");
        messages.put("firewall.status", "Status");
        messages.put("firewall.active", "Active");
        messages.put("firewall.inactive", "Inactive");

        messages.put("docker.title", "Docker Management");
        messages.put("docker.containers", "Containers");
        messages.put("docker.start", "Start");
        messages.put("docker.stop", "Stop");
        messages.put("docker.restart", "Restart");
        messages.put("docker.logs", "Logs");
        messages.put("docker.status", "Status");

        messages.put("updates.title", "System Updates");
        messages.put("updates.check", "Check for Updates");
        messages.put("updates.available", "Updates Available");
        messages.put("updates.upToDate", "System is up to date");
        messages.put("updates.install", "Install Updates");
        messages.put("updates.security", "Security Updates");

        messages.put("health.title", "Health Check");
        messages.put("health.run", "Run Health Check");
        messages.put("health.ssh", "SSH Configuration");
        messages.put("health.sudoers", "Sudoers");
        messages.put("health.nftables", "NFTables");
        messages.put("health.scripts", "Scripts");
        messages.put("health.passed", "Passed");
        messages.put("health.failed", "Failed");
        messages.put("health.warning", "Warning");

        messages.put("tooltip.addServer", "Add a new server to manage");
        messages.put("tooltip.removeServer", "Remove server from list");
        messages.put("tooltip.refresh", "Refresh data");
    }

    private void loadFrenchMessages() {
        messages.put("app.title", "RISE - Remote Infrastructure Security & Efficiency");
        messages.put("server.add", "Ajouter un serveur");
        messages.put("dialog.cancel", "Cancel");
        messages.put("dialog.ok", "OK");
        messages.put("dialog.error", "Error");
        messages.put("status.connecting", "Connexion...");
    }

    /**
     * Get a message by key
     */
    public String get(String key) {
        return messages.getOrDefault(key, key);
    }

    /**
     * Get a message with parameters
     */
    public String get(String key, Object... args) {
        String template = messages.getOrDefault(key, key);
        try {
            return String.format(template, args);
        } catch (Exception e) {
            return template;
        }
    }

    /**
     * Force refresh from GitHub
     */
    public void refreshFromGitHub() {
        loadedVersion = null;
        loadMessages(currentLanguage);
    }
}
