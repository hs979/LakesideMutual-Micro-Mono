package com.lakesidemutual.application;

import java.util.Date;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import com.lakesidemutual.domain.selfservice.InsuranceQuoteEntity;
import com.lakesidemutual.domain.selfservice.InsuranceQuoteRequestAggregateRoot;
import com.lakesidemutual.domain.selfservice.MoneyAmount;
import com.lakesidemutual.infrastructure.SelfServiceInsuranceQuoteRequestRepository;

/**
 * SelfServiceQuoteEventListener handles ApplicationEvents published by the policy module.
 * It replaces the JMS consumers: InsuranceQuoteResponseMessageConsumer,
 * InsuranceQuoteExpiredMessageConsumer, and PolicyCreatedMessageConsumer.
 */
@Component
public class SelfServiceQuoteEventListener {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private SelfServiceInsuranceQuoteRequestRepository insuranceQuoteRequestRepository;

	@EventListener
	public void onQuoteResponse(InsuranceQuoteResponseApplicationEvent event) {
		logger.info("Processing InsuranceQuoteResponseApplicationEvent for request id={}", event.getInsuranceQuoteRequestId());
		Optional<InsuranceQuoteRequestAggregateRoot> opt = insuranceQuoteRequestRepository.findById(event.getInsuranceQuoteRequestId());
		if (!opt.isPresent()) {
			logger.error("Unable to process insurance quote response event: invalid insurance quote request id.");
			return;
		}

		InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = opt.get();
		if (event.isRequestAccepted()) {
			Date expirationDate = event.getExpirationDate();
			MoneyAmount insurancePremium = event.getInsurancePremium() != null ?
				new MoneyAmount(event.getInsurancePremium().getAmount(), java.util.Currency.getInstance(event.getInsurancePremium().getCurrency())) : null;
			MoneyAmount policyLimit = event.getPolicyLimit() != null ?
				new MoneyAmount(event.getPolicyLimit().getAmount(), java.util.Currency.getInstance(event.getPolicyLimit().getCurrency())) : null;
			InsuranceQuoteEntity insuranceQuote = new InsuranceQuoteEntity(expirationDate, insurancePremium, policyLimit);
			insuranceQuoteRequest.acceptRequest(insuranceQuote, new Date());
		} else {
			insuranceQuoteRequest.rejectRequest(new Date());
		}
		insuranceQuoteRequestRepository.save(insuranceQuoteRequest);
	}

	@EventListener
	public void onQuoteExpired(InsuranceQuoteExpiredApplicationEvent event) {
		logger.info("Processing InsuranceQuoteExpiredApplicationEvent for request id={}", event.getInsuranceQuoteRequestId());
		Optional<InsuranceQuoteRequestAggregateRoot> opt = insuranceQuoteRequestRepository.findById(event.getInsuranceQuoteRequestId());
		if (!opt.isPresent()) {
			logger.error("Unable to process insurance quote expired event: invalid insurance quote request id.");
			return;
		}

		InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = opt.get();
		insuranceQuoteRequest.markQuoteAsExpired(event.getExpirationDate());
		insuranceQuoteRequestRepository.save(insuranceQuoteRequest);
	}

	@EventListener
	public void onPolicyCreated(PolicyCreatedApplicationEvent event) {
		logger.info("Processing PolicyCreatedApplicationEvent for request id={}", event.getInsuranceQuoteRequestId());
		Optional<InsuranceQuoteRequestAggregateRoot> opt = insuranceQuoteRequestRepository.findById(event.getInsuranceQuoteRequestId());
		if (!opt.isPresent()) {
			logger.error("Unable to process policy created event: invalid insurance quote request id.");
			return;
		}

		InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = opt.get();
		insuranceQuoteRequest.finalizeQuote(event.getPolicyId(), event.getDate());
		insuranceQuoteRequestRepository.save(insuranceQuoteRequest);
	}
}
