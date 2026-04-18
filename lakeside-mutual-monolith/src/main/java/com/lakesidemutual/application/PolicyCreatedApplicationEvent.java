package com.lakesidemutual.application;

import java.util.Date;
import org.springframework.context.ApplicationEvent;

public class PolicyCreatedApplicationEvent extends ApplicationEvent {
	private final Date date;
	private final Long insuranceQuoteRequestId;
	private final String policyId;

	public PolicyCreatedApplicationEvent(Object source, Date date, Long insuranceQuoteRequestId, String policyId) {
		super(source);
		this.date = date;
		this.insuranceQuoteRequestId = insuranceQuoteRequestId;
		this.policyId = policyId;
	}

	public Date getDate() { return date; }
	public Long getInsuranceQuoteRequestId() { return insuranceQuoteRequestId; }
	public String getPolicyId() { return policyId; }
}
