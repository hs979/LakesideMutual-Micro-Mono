package com.lakesidemutual.application;

import java.util.Date;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.lakesidemutual.domain.selfservice.CustomerInfoEntity;
import com.lakesidemutual.domain.selfservice.InsuranceOptionsEntity;
import com.lakesidemutual.domain.selfservice.InsuranceQuoteRequestAggregateRoot;
import com.lakesidemutual.domain.selfservice.RequestStatus;
import com.lakesidemutual.infrastructure.SelfServiceInsuranceQuoteRequestRepository;
import com.lakesidemutual.interfaces.dtos.selfservice.insurancequoterequest.InsuranceQuoteRequestDto;

/**
 * SelfServiceQuoteService encapsulates the orchestration logic previously in
 * PolicyManagementMessageProducer. Instead of sending JMS messages, it directly
 * calls PolicyQuoteService.
 */
@Service
public class SelfServiceQuoteService {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private SelfServiceInsuranceQuoteRequestRepository insuranceQuoteRequestRepository;

	@Autowired
	private PolicyQuoteService policyQuoteService;

	public InsuranceQuoteRequestAggregateRoot createQuoteRequest(Date date, InsuranceQuoteRequestDto requestDto) {
		logger.info("Creating a new insurance quote request.");

		CustomerInfoEntity customerInfoEntity = requestDto.getCustomerInfo().toDomainObject();
		InsuranceOptionsEntity insuranceOptionsEntity = requestDto.getInsuranceOptions().toDomainObject();
		InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = new InsuranceQuoteRequestAggregateRoot(date, RequestStatus.REQUEST_SUBMITTED, customerInfoEntity, insuranceOptionsEntity, null, null);
		insuranceQuoteRequestRepository.save(insuranceQuoteRequest);

		InsuranceQuoteRequestDto savedDto = InsuranceQuoteRequestDto.fromDomainObject(insuranceQuoteRequest);

		com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestDto policyDto = convertToPolicyDto(savedDto);
		policyQuoteService.receiveInsuranceQuoteRequest(policyDto);

		return insuranceQuoteRequest;
	}

	public void handleCustomerDecision(Date date, Long insuranceQuoteRequestId, boolean quoteAccepted) {
		logger.info("Processing customer decision for quote request id={}, accepted={}", insuranceQuoteRequestId, quoteAccepted);
		policyQuoteService.handleCustomerDecision(insuranceQuoteRequestId, quoteAccepted, date);
	}

	private com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestDto convertToPolicyDto(InsuranceQuoteRequestDto ssDto) {
		com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestDto policyDto = new com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestDto();
		policyDto.setId(ssDto.getId());
		policyDto.setDate(ssDto.getDate());
		policyDto.setStatusHistory(ssDto.getStatusHistory().stream().map(sc -> {
			com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.RequestStatusChangeDto rsc = new com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.RequestStatusChangeDto();
			rsc.setDate(sc.getDate());
			rsc.setStatus(sc.getStatus());
			return rsc;
		}).collect(java.util.stream.Collectors.toList()));

		if (ssDto.getCustomerInfo() != null) {
			com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.CustomerInfoDto ci = new com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.CustomerInfoDto();
			ci.setCustomerId(ssDto.getCustomerInfo().getCustomerId());
			ci.setFirstname(ssDto.getCustomerInfo().getFirstname());
			ci.setLastname(ssDto.getCustomerInfo().getLastname());
			if (ssDto.getCustomerInfo().getContactAddress() != null) {
				com.lakesidemutual.interfaces.dtos.policy.customer.AddressDto contactAddr = new com.lakesidemutual.interfaces.dtos.policy.customer.AddressDto();
				contactAddr.setStreetAddress(ssDto.getCustomerInfo().getContactAddress().getStreetAddress());
				contactAddr.setPostalCode(ssDto.getCustomerInfo().getContactAddress().getPostalCode());
				contactAddr.setCity(ssDto.getCustomerInfo().getContactAddress().getCity());
				ci.setContactAddress(contactAddr);
			}
			if (ssDto.getCustomerInfo().getBillingAddress() != null) {
				com.lakesidemutual.interfaces.dtos.policy.customer.AddressDto billingAddr = new com.lakesidemutual.interfaces.dtos.policy.customer.AddressDto();
				billingAddr.setStreetAddress(ssDto.getCustomerInfo().getBillingAddress().getStreetAddress());
				billingAddr.setPostalCode(ssDto.getCustomerInfo().getBillingAddress().getPostalCode());
				billingAddr.setCity(ssDto.getCustomerInfo().getBillingAddress().getCity());
				ci.setBillingAddress(billingAddr);
			} else if (ssDto.getCustomerInfo().getContactAddress() != null) {
				com.lakesidemutual.interfaces.dtos.policy.customer.AddressDto billingAddr = new com.lakesidemutual.interfaces.dtos.policy.customer.AddressDto();
				billingAddr.setStreetAddress(ssDto.getCustomerInfo().getContactAddress().getStreetAddress());
				billingAddr.setPostalCode(ssDto.getCustomerInfo().getContactAddress().getPostalCode());
				billingAddr.setCity(ssDto.getCustomerInfo().getContactAddress().getCity());
				ci.setBillingAddress(billingAddr);
			}
			policyDto.setCustomerInfo(ci);
		}

		if (ssDto.getInsuranceOptions() != null) {
			com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceOptionsDto io = new com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceOptionsDto();
			io.setStartDate(ssDto.getInsuranceOptions().getStartDate());
			io.setInsuranceType(ssDto.getInsuranceOptions().getInsuranceType());
			if (ssDto.getInsuranceOptions().getDeductible() != null) {
				io.setDeductible(new com.lakesidemutual.interfaces.dtos.policy.policy.MoneyAmountDto(
					ssDto.getInsuranceOptions().getDeductible().getAmount(),
					ssDto.getInsuranceOptions().getDeductible().getCurrency()
				));
			}
			policyDto.setInsuranceOptions(io);
		}

		return policyDto;
	}
}
