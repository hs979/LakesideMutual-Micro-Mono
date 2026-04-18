package com.lakesidemutual.interfaces.policy;

import java.util.Date;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import jakarta.validation.Valid;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.lakesidemutual.domain.policy.InsuranceQuoteRequestAggregateRoot;
import com.lakesidemutual.domain.policy.RequestStatus;
import com.lakesidemutual.application.PolicyQuoteService;
import com.lakesidemutual.infrastructure.PolicyInsuranceQuoteRequestRepository;
import com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestDto;
import com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteRequestNotFoundException;
import com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest.InsuranceQuoteResponseDto;
import com.lakesidemutual.interfaces.dtos.policy.policy.MoneyAmountDto;

/**
 * This REST controller gives clients access to the insurance quote requests. It is an example of the
 * <i>Information Holder Resource</i> pattern. This particular one is a special type of information holder called <i>Operational Data Holder</i>.
 *
 * @see <a href="https://www.microservice-api-patterns.org/patterns/responsibility/informationHolderEndpointTypes/OperationalDataHolder">Operational Data Holder</a>
 * 
 * As it supports responding to requests, you can also view it as a Processing Resource:
 * 
 *  * @see <a href="https://www.microservice-api-patterns.org/patterns/responsibility/endpointRoles/ProcessingResource">Processing Resource</a>
 *  
 *Matching RDD role stereotypes are <i>Coordinator</i> and <i>Information Holder</i>:
 *
 *  * @see <a href="http://www.wirfs-brock.com/PDFs/A_Brief-Tour-of-RDD.pdf">A Brief Tour of RDD</a>
 */
@RestController
@RequestMapping("/api/policy/insurance-quote-requests")
public class PolicyQuoteController {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private PolicyInsuranceQuoteRequestRepository insuranceQuoteRequestRepository;

	@Autowired
	private PolicyQuoteService policyQuoteService;

	@Operation(summary = "Get all Insurance Quote Requests.")
	@GetMapping
	public ResponseEntity<List<InsuranceQuoteRequestDto>> getInsuranceQuoteRequests() {
		logger.debug("Fetching all Insurance Quote Requests");
		List<InsuranceQuoteRequestAggregateRoot> quoteRequests = insuranceQuoteRequestRepository.findAllByOrderByDateDesc();
		List<InsuranceQuoteRequestDto> quoteRequestDtos = quoteRequests.stream().map(InsuranceQuoteRequestDto::fromDomainObject).collect(Collectors.toList());
		return ResponseEntity.ok(quoteRequestDtos);
	}

	@Operation(summary = "Get a specific Insurance Quote Request.")
	@GetMapping(value = "/{id}") /* MAP: Retrieval Operation */
	public ResponseEntity<InsuranceQuoteRequestDto> getInsuranceQuoteRequest(@Parameter(description = "the insurance quote request's unique id", required = true) @PathVariable Long id) {
		logger.debug("Fetching Insurance Quote Request with id '{}'", id);
		Optional<InsuranceQuoteRequestAggregateRoot> optInsuranceQuoteRequest = insuranceQuoteRequestRepository.findById(id);
		if (!optInsuranceQuoteRequest.isPresent()) {
			final String errorMessage = "Failed to find an Insurance Quote Request with id '{}'";
			logger.warn(errorMessage, id);
			throw new InsuranceQuoteRequestNotFoundException(errorMessage);
		}

		InsuranceQuoteRequestAggregateRoot insuranceQuoteRequest = optInsuranceQuoteRequest.get();
		InsuranceQuoteRequestDto insuranceQuoteRequestDto = InsuranceQuoteRequestDto.fromDomainObject(insuranceQuoteRequest);
		return ResponseEntity.ok(insuranceQuoteRequestDto);
	}

	@Operation(summary = "Updates the status of an existing Insurance Quote Request")
	@PatchMapping(value = "/{id}") /* MAP: State Transition Operation */
	public ResponseEntity<InsuranceQuoteRequestDto> respondToInsuranceQuoteRequest(
			@Parameter(description = "the insurance quote request's unique id", required = true) @PathVariable Long id,
			@Parameter(description = "the response that contains a new insurance quote if the request has been accepted", required = true)
			@Valid @RequestBody InsuranceQuoteResponseDto insuranceQuoteResponseDto) {

		logger.debug("Responding to Insurance Quote Request with id '{}'", id);

		Optional<InsuranceQuoteRequestAggregateRoot> optInsuranceQuoteRequest = insuranceQuoteRequestRepository.findById(id);
		if (!optInsuranceQuoteRequest.isPresent()) {
			final String errorMessage = "Failed to respond to Insurance Quote Request, because there is no Insurance Quote Request with id '{}'";
			logger.warn(errorMessage, id);
			throw new InsuranceQuoteRequestNotFoundException(errorMessage);
		}

		final Date date = new Date();
		if(insuranceQuoteResponseDto.getStatus().equals(RequestStatus.QUOTE_RECEIVED.toString())) {
			logger.info("Insurance Quote Request with id '{}' has been accepted", id);
			Date expirationDate = insuranceQuoteResponseDto.getExpirationDate();
			MoneyAmountDto insurancePremiumDto = insuranceQuoteResponseDto.getInsurancePremium();
			MoneyAmountDto policyLimitDto = insuranceQuoteResponseDto.getPolicyLimit();
			policyQuoteService.respondToQuoteRequest(id, true, date, expirationDate, insurancePremiumDto, policyLimitDto);
		} else if(insuranceQuoteResponseDto.getStatus().equals(RequestStatus.REQUEST_REJECTED.toString())) {
			logger.info("Insurance Quote Request with id '{}' has been rejected", id);
			policyQuoteService.respondToQuoteRequest(id, false, date, null, null, null);
		}

		InsuranceQuoteRequestAggregateRoot updated = insuranceQuoteRequestRepository.findById(id).orElse(null);
		InsuranceQuoteRequestDto insuranceQuoteRequestDto = updated != null ? InsuranceQuoteRequestDto.fromDomainObject(updated) : null;
		return ResponseEntity.ok(insuranceQuoteRequestDto);
	}
}