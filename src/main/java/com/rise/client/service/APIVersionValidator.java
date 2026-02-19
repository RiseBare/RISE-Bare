package com.rise.client.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Exception for API version validation failures
 */
public class APIVersionException extends Exception {
    private static final Logger LOG = LoggerFactory.getLogger(APIVersionException.class);

    public APIVersionException(String message) {
        super(message);
    }
}

/**
 * API Version Validator
 * V5.9: Enhanced validation with format check and better error messages
 */
public class APIVersionValidator {
    private static final String CLIENT_API_VERSION = "1.0";

    /**
     * Validate server API version against client version
     */
    public static void validateApiVersion(String serverVersion) throws APIVersionException {
        // Validate format before splitting
        if (serverVersion == null || !serverVersion.matches("\\d+\\.\\d+")) {
            throw new APIVersionException(
                "Malformed API version from server: " + serverVersion);
        }

        String[] serverParts = serverVersion.split("\\.");
        String[] clientParts = CLIENT_API_VERSION.split("\\.");

        int serverMajor = Integer.parseInt(serverParts[0]);
        int serverMinor = Integer.parseInt(serverParts[1]);
        int clientMajor = Integer.parseInt(clientParts[0]);
        int clientMinor = Integer.parseInt(clientParts[1]);

        // Major version MUST match
        if (serverMajor != clientMajor) {
            throw new APIVersionException(String.format(
                "Incompatible major version: client %d.x vs server %d.x\n" +
                "Please update your client or server to matching versions.",
                clientMajor, serverMajor
            ));
        }

        // Minor version checks (warnings only in V5.9)
        if (serverMinor > clientMinor + 2) {
            // Server is significantly newer
            LOG.warn(String.format(
                "Server API (%s) is significantly newer than client (%s).\n" +
                "Some features may not work correctly. Consider updating the client.",
                serverVersion, CLIENT_API_VERSION
            ));
        } else if (serverMinor < clientMinor - 1) {
            // Server is older
            LOG.warn(String.format(
                "Server API (%s) is older than client (%s).\n" +
                "Consider running setup-env.sh --update on the server.",
                serverVersion, CLIENT_API_VERSION
            ));
        }
    }
}
