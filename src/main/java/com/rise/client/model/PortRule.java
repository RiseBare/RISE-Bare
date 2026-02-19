package com.rise.client.model;

import javafx.beans.property.SimpleIntegerProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;
import javafx.beans.property.IntegerProperty;

/**
 * PortRule model for firewall rules
 */
public class PortRule {
    private final IntegerProperty port;
    private final StringProperty proto;
    private final StringProperty action;
    private final StringProperty cidr;
    private final StringProperty status;

    public PortRule(int port, String proto, String action, String cidr) {
        this.port = new SimpleIntegerProperty(port);
        this.proto = new SimpleStringProperty(proto);
        this.action = new SimpleStringProperty(action);
        this.cidr = new SimpleStringProperty(cidr);
        this.status = new SimpleStringProperty("unknown");
    }

    public int getPort() { return port.get(); }
    public IntegerProperty portProperty() { return port; }

    public String getProto() { return proto.get(); }
    public StringProperty protoProperty() { return proto; }

    public String getAction() { return action.get(); }
    public StringProperty actionProperty() { return action; }

    public String getCidr() { return cidr.get(); }
    public StringProperty cidrProperty() { return cidr; }

    public String getStatus() { return status.get(); }
    public StringProperty statusProperty() { return status; }

    public void setStatus(String status) { this.status.set(status); }
}
