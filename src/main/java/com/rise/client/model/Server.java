package com.rise.client.model;

import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

/**
 * Server model representing a managed server
 */
public class Server {
    private final StringProperty id;
    private final StringProperty name;
    private final StringProperty host;
    private final int port;
    private final StringProperty username;

    public Server(String id, String name, String host, int port, String username) {
        this.id = new SimpleStringProperty(id);
        this.name = new SimpleStringProperty(name);
        this.host = new SimpleStringProperty(host);
        this.port = port;
        this.username = new SimpleStringProperty(username);
    }

    public String getId() { return id.get(); }
    public StringProperty idProperty() { return id; }

    public String getName() { return name.get(); }
    public StringProperty nameProperty() { return name; }

    public String getHost() { return host.get(); }
    public StringProperty hostProperty() { return host; }

    public int getPort() { return port; }

    public String getUsername() { return username.get(); }
    public StringProperty usernameProperty() { return username; }
}
