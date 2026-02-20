package com.rise.client.config;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rise.client.i18n.Messages;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Application settings stored in config.json
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class AppSettings {

    private static final Path CONFIG_PATH = Paths.get(
        System.getProperty("user.home"), ".rise", "config.json"
    );

    private String language = "en";
    private boolean autoUpdateScripts = true;
    private String theme = "light";

    private static AppSettings instance;

    private AppSettings() {}

    public static synchronized AppSettings getInstance() {
        if (instance == null) {
            instance = load();
        }
        return instance;
    }

    public static AppSettings load() {
        try {
            if (Files.exists(CONFIG_PATH)) {
                ObjectMapper mapper = new ObjectMapper();
                return mapper.readValue(CONFIG_PATH.toFile(), AppSettings.class);
            }
        } catch (IOException e) {
            System.err.println("Failed to load settings: " + e.getMessage());
        }
        return new AppSettings();
    }

    public void save() {
        try {
            Files.createDirectories(CONFIG_PATH.getParent());
            ObjectMapper mapper = new ObjectMapper();
            mapper.writerWithDefaultPrettyPrinter()
                .writeValue(CONFIG_PATH.toFile(), this);

            // Apply language setting
            Messages.getInstance().setLanguage(language);
        } catch (IOException e) {
            System.err.println("Failed to save settings: " + e.getMessage());
        }
    }

    // Getters and setters
    public String getLanguage() { return language; }
    public void setLanguage(String language) {
        this.language = language;
        Messages.getInstance().setLanguage(language);
    }

    public boolean isAutoUpdateScripts() { return autoUpdateScripts; }
    public void setAutoUpdateScripts(boolean autoUpdateScripts) {
        this.autoUpdateScripts = autoUpdateScripts;
    }

    public String getTheme() { return theme; }
    public void setTheme(String theme) { this.theme = theme; }
}
