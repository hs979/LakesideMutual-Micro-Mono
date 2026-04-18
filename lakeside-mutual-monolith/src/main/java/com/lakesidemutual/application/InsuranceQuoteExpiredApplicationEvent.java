package com.lakesidemutual.application;

import java.util.Date;
import org.springframework.context.ApplicationEvent;

public class InsuranceQuoteExpiredApplicationEvent extends ApplicationEvent {
	private final Date expirationDate;
	private final Long insuranceQuoteRequestId;

	public InsuranceQuoteExpiredApplicationEvent(Object source, Date expirationDate, Long insuranceQuoteRequestId) {
		super(source);
		this.expirationDate = expirationDate;
		this.insuranceQuoteRequestId = insuranceQuoteRequestId;
	}

	public Date getExpirationDate() { return expirationDate; }
	public Long getInsuranceQuoteRequestId() { return insuranceQuoteRequestId; }
}
