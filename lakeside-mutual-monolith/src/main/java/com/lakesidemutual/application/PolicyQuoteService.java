package com.lakesidemutual.application;

import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import com.lakesidemutual.domain.customer.CustomerId;
import com.lakesidemutual.domain.policy.CustomerInfoEntity;
import com.lakesidemutual.domain.policy.InsuranceOptionsEntity;
import com.lakesidemutual.domain.policy.InsuranceQuoteEntity;
import com.lakesidemutual.domain.policy.InsuranceQuoteRequestAggregateRoot;
import com.lakesidemutual.domain.policy.RequestStatus;
import com.lakesidemutual.domain.policy.MoneyAmount;
import com.lakesidemutual.domain.policy.PolicyAggregateRoot;
import com.lakesidemutual.domain.policy.PolicyId;
import com.lakesidemutual.domain.policy.PolicyPeriod;
import com.lakesidemutual.domain.policy.PolicyType;
import com.lakesidemutual.domain.policy.InsuringAgreementEntity;
import com.lakesidemutual.infrastructure.PolicyInsuranceQuoteRequestRepository;
import com.lakesidemutual.infrastructure.PolicyRepository;
import com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestDto;
import com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.RequestStatusChangeDto;
import com.lakesidemutual.interfaces.dtos.policy.policy.MoneyAmountDto;

/**
 * PolicyQuoteService encapsulates the business logic that was previously in
 * InsuranceQuoteRequestMessageConsumer and CustomerDecisionMessageConsumer.
 * It handles creating quote requests on the policy side and processing customer decisions.
 */
@Service
public class PolicyQuoteService {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private PolicyInsuranceQuoteRequestRepository insuranceQuoteRequestRepository;

	@Autowired
	private PolicyRepository policyRepository;

	@Autowired
	private ApplicationEventPublisher eventPublisher;

	public void receiveInsuranceQuoteRequest(InsuranceQuoteRequestDto insuranceQuoteRequestDto) {
		logger.info("Processing a new InsuranceQuoteRequest on the policy side.");
		Long id = insuranceQuoteRequestDto.getId();
		Date date = insuranceQuoteRequestDto.getDate();
		List<RequestStatusChangeDto> statusHistory = insuranceQuoteRequestDto.getStatusHistory();
		RequestStatus status = RequestStatus.valueOf(statusHistory.get(statusHistory.size() - 1).getStatus());

		CustomerInfoEntity customerInfo = insuranceQuoteRequestDto.getCustomerInfo().toDomainObject();
		InsuranceOptionsEntity insuranceOptions = insuranceQuoteRequestDto.getInsuranceOptions().toDomainObject();

		InsuranceQuoteRequestAggregateRoot insuranceQuoteAggregateRoot = new InsuranceQuoteRequestAggregateRoot(id, date, status, customerInfo, insuranceOptions, null, null);
		insuranceQuoteRequestRepository.save(insuranceQuoteAggregateRoot);
	}

	public void handleCustomerDecision(Long insuranceQuoteRequestId, boolean quoteAccepted, Date decisionDate) {
		logger.debug("Processing CustomerDecision for quote request id={}", insuranceQuoteRequestId);
		final Optional<InsuranceQuoteRequestAggregateRoot> insuranceQuoteRequestOpt = insuranceQuoteRequestRepository.findById(insuranceQuoteRequestId);

		if (!insuranceQuoteRequestOpt.isPresent()) {
			logger.error("Unable to process a customer decision with an invalid insurance quote request id.");
			return;
		}

		final InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = insuranceQuoteRequestOpt.get();

		if (quoteAccepted) {
			if (insuranceQuoteRequest.getStatus().equals(RequestStatus.QUOTE_EXPIRED) || insuranceQuoteRequest.hasQuoteExpired(decisionDate)) {
				Date expirationDate;
				if (insuranceQuoteRequest.getStatus().equals(RequestStatus.QUOTE_EXPIRED)) {
					expirationDate = insuranceQuoteRequest.popStatus().getDate();
				} else {
					expirationDate = decisionDate;
				}

				insuranceQuoteRequest.acceptQuote(decisionDate);
				insuranceQuoteRequest.markQuoteAsExpired(expirationDate);
				eventPublisher.publishEvent(new InsuranceQuoteExpiredApplicationEvent(this, expirationDate, insuranceQuoteRequest.getId()));
			} else {
				logger.info("The insurance quote for request {} has been accepted", insuranceQuoteRequest.getId());
				insuranceQuoteRequest.acceptQuote(decisionDate);
				PolicyAggregateRoot policy = createPolicyForInsuranceQuoteRequest(insuranceQuoteRequest);
				policyRepository.save(policy);
				String policyId = policy.getId().getId();
				Date policyCreationDate = new Date();
				insuranceQuoteRequest.finalizeQuote(policyId, policyCreationDate);

				eventPublisher.publishEvent(new PolicyCreatedApplicationEvent(this, policyCreationDate, insuranceQuoteRequest.getId(), policyId));
			}
		} else {
			if (insuranceQuoteRequest.getStatus().equals(RequestStatus.QUOTE_EXPIRED)) {
				insuranceQuoteRequest.popStatus();
			}

			logger.info("The insurance quote for request {} has been rejected", insuranceQuoteRequest.getId());
			insuranceQuoteRequest.rejectQuote(decisionDate);
		}

		insuranceQuoteRequestRepository.save(insuranceQuoteRequest);
	}

	public void respondToQuoteRequest(Long insuranceQuoteRequestId, boolean accepted, Date date, Date expirationDate, MoneyAmountDto insurancePremiumDto, MoneyAmountDto policyLimitDto) {
		Optional<InsuranceQuoteRequestAggregateRoot> optInsuranceQuoteRequest = insuranceQuoteRequestRepository.findById(insuranceQuoteRequestId);
		if (!optInsuranceQuoteRequest.isPresent()) {
			logger.error("Insurance quote request not found: {}", insuranceQuoteRequestId);
			return;
		}

		InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = optInsuranceQuoteRequest.get();
		if (accepted) {
			MoneyAmount insurancePremium = insurancePremiumDto.toDomainObject();
			MoneyAmount policyLimit = policyLimitDto.toDomainObject();
			InsuranceQuoteEntity insuranceQuote = new InsuranceQuoteEntity(expirationDate, insurancePremium, policyLimit);
			insuranceQuoteRequest.acceptRequest(insuranceQuote, date);
		} else {
			insuranceQuoteRequest.rejectRequest(date);
		}
		insuranceQuoteRequestRepository.save(insuranceQuoteRequest);

		eventPublisher.publishEvent(new InsuranceQuoteResponseApplicationEvent(this, insuranceQuoteRequestId, accepted, expirationDate, insurancePremiumDto, policyLimitDto));
	}

	private PolicyAggregateRoot createPolicyForInsuranceQuoteRequest(InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest) {
		PolicyId policyId = PolicyId.random();
		CustomerId customerId = insuranceQuoteRequest.getCustomerInfo().getCustomerId();

		Date startDate = insuranceQuoteRequest.getInsuranceOptions().getStartDate();
		Calendar calendar = Calendar.getInstance();
		calendar.setTime(startDate);
		calendar.add(Calendar.YEAR, 1);
		Date endDate = calendar.getTime();
		PolicyPeriod policyPeriod = new PolicyPeriod(startDate, endDate);

		PolicyType policyType = new PolicyType(insuranceQuoteRequest.getInsuranceOptions().getInsuranceType().getName());
		MoneyAmount deductible = insuranceQuoteRequest.getInsuranceOptions().getDeductible();
		MoneyAmount insurancePremium = insuranceQuoteRequest.getInsuranceQuote().getInsurancePremium();
		MoneyAmount policyLimit = insuranceQuoteRequest.getInsuranceQuote().getPolicyLimit();
		InsuringAgreementEntity insuringAgreement = new InsuringAgreementEntity(Collections.emptyList());
		return new PolicyAggregateRoot(policyId, customerId, new Date(), policyPeriod, policyType, deductible, policyLimit, insurancePremium, insuringAgreement);
	}
}
