package com.lakesidemutual.domain.selfservice;

import jakarta.persistence.AttributeOverride;
import jakarta.persistence.AttributeOverrides;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

import com.lakesidemutual.domain.selfservice.Address;
import com.lakesidemutual.domain.customer.CustomerId;

/**
 * CustomerInfoEntity is an entity that is part of an InsuranceQuoteRequestAggregateRoot
 * and contains infos about the initiator of the request.
 */
@Entity(name = "SelfServiceCustomerInfoEntity")
@jakarta.persistence.Table(name = "ss_customer_info")
public class CustomerInfoEntity implements org.microserviceapipatterns.domaindrivendesign.Entity {
	@GeneratedValue
	@Id
	private Long id;

	@Embedded
	@AttributeOverrides({
		@AttributeOverride(name="id", column=@Column(name="customerId"))})
	private final CustomerId customerId;

	private final String firstname;

	private final String lastname;

	@OneToOne(cascade = CascadeType.ALL)
	private final Address contactAddress;

	@OneToOne(cascade = CascadeType.ALL)
	private final Address billingAddress;

	public CustomerInfoEntity() {
		this.customerId = null;
		this.firstname = null;
		this.lastname = null;
		this.contactAddress = null;
		this.billingAddress = null;
	}

	public CustomerInfoEntity(CustomerId customerId, String firstname, String lastname, Address contactAddress, Address billingAddress) {
		this.customerId = customerId;
		this.firstname = firstname;
		this.lastname = lastname;
		this.contactAddress = contactAddress;
		this.billingAddress = billingAddress;
	}

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}

	public CustomerId getCustomerId() {
		return customerId;
	}

	public String getFirstname() {
		return firstname;
	}

	public String getLastname() {
		return lastname;
	}

	public Address getContactAddress() {
		return contactAddress;
	}

	public Address getBillingAddress() {
		return billingAddress;
	}
}
