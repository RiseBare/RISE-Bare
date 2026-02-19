package com.rise.client;

import com.rise.client.security.KeyManager;
import com.rise.client.service.SSHCommandExecutor;
import com.rise.client.ui.MainController;
import javafx.application.Application;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Stage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * RISE Client Application
 * Main entry point for the JavaFX desktop client
 */
public class RISEApplication extends Application {
    private static final Logger LOG = LoggerFactory.getLogger(RISEApplication.class);

    @Override
    public void start(Stage primaryStage) throws Exception {
        LOG.info("Starting RISE Client v1.0.0");

        // V5.9: Initialize secure key storage FIRST
        try {
            KeyManager.initializeSecureStorage();
        } catch (IOException e) {
            LOG.error("Failed to initialize secure storage", e);
            showErrorAndExit("Failed to initialize secure storage", e);
            return;
        }

        // Load main UI
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/fxml/main.fxml"));
            Parent root = loader.load();

            MainController controller = loader.getController();
            controller.setStage(primaryStage);

            primaryStage.setTitle("RISE - Remote Infrastructure Security & Efficiency");
            primaryStage.setScene(new Scene(root, 1024, 768));
            primaryStage.setMinWidth(800);
            primaryStage.setMinHeight(600);
            primaryStage.show();

            LOG.info("RISE Client started successfully");
        } catch (IOException e) {
            LOG.error("Failed to load UI", e);
            showErrorAndExit("Failed to load UI", e);
        }
    }

    private void showErrorAndExit(String message, Exception e) {
        javafx.scene.control.Alert alert = new javafx.scene.control.Alert(
            javafx.scene.control.Alert.AlertType.ERROR
        );
        alert.setTitle("RISE Client Error");
        alert.setHeaderText(message);
        alert.setContentText(e.getMessage());
        alert.showAndWait();
        javafx.application.Platform.exit();
    }

    @Override
    public void stop() throws Exception {
        LOG.info("RISE Client shutting down");
        super.stop();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
