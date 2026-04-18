package com.lakesidemutual.application;

import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

import org.quartz.Job;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;

import com.lakesidemutual.domain.policy.InsuranceQuoteRequestAggregateRoot;
import com.lakesidemutual.infrastructure.PolicyInsuranceQuoteRequestRepository;

public class ExpirationCheckerJob implements Job {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private ApplicationEventPublisher eventPublisher;

	@Autowired
	private PolicyInsuranceQuoteRequestRepository insuranceQuoteRequestRepository;

	@Override
	public void execute(JobExecutionContext context) throws JobExecutionException {
		logger.debug("Checking for expired insurance quotes...");

		final Date date = new Date();
		List<InsuranceQuoteRequestAggregateRoot> quoteRequests = insuranceQuoteRequestRepository.findAll();
		List<InsuranceQuoteRequestAggregateRoot> expiredQuoteRequests = quoteRequests.stream()
				.filter(quoteRequest -> quoteRequest.checkQuoteExpirationDate(date))
				.collect(Collectors.toList());
		insuranceQuoteRequestRepository.saveAll(expiredQuoteRequests);
		expiredQuoteRequests.forEach(expiredQuoteRequest -> {
			eventPublisher.publishEvent(new InsuranceQuoteExpiredApplicationEvent(this, date, expiredQuoteRequest.getId()));
		});

		if(expiredQuoteRequests.size() > 0) {
			logger.info("Found {} expired insurance quotes", expiredQuoteRequests.size());
		} else {
			logger.debug("Found no expired insurance quotes");
		}
	}
}
