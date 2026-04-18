package com.lakesidemutual.interfaces.policy;

import static org.springframework.hateoas.server.mvc.WebMvcLinkBuilder.linkTo;
import static org.springframework.hateoas.server.mvc.WebMvcLinkBuilder.methodOn;

import java.util.List;
import java.util.stream.Collectors;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.hateoas.Link;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.lakesidemutual.application.CustomerService;
import com.lakesidemutual.application.Page;
import com.lakesidemutual.domain.customer.CustomerAggregateRoot;
import com.lakesidemutual.domain.customer.CustomerId;
import com.lakesidemutual.domain.policy.PolicyAggregateRoot;
import com.lakesidemutual.infrastructure.PolicyRepository;
import com.lakesidemutual.interfaces.dtos.policy.customer.CustomerDto;
import com.lakesidemutual.interfaces.dtos.policy.customer.CustomerIdDto;
import com.lakesidemutual.interfaces.dtos.policy.customer.CustomerNotFoundException;
import com.lakesidemutual.interfaces.dtos.policy.customer.PaginatedCustomerResponseDto;
import com.lakesidemutual.interfaces.dtos.policy.policy.PolicyDto;

@RestController
@RequestMapping("/api/policy/customers")
public class PolicyCustomerController {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private PolicyRepository policyRepository;

	@Autowired
	private CustomerService customerService;

	@Operation(summary = "Get all customers.")
	@GetMapping
	public ResponseEntity<PaginatedCustomerResponseDto> getCustomers(
			@Parameter(description = "search terms to filter the customers by name", required = false) @RequestParam(value = "filter", required = false, defaultValue = "") String filter,
			@Parameter(description = "the maximum number of customers per page", required = false) @RequestParam(value = "limit", required = false, defaultValue = "10") Integer limit,
			@Parameter(description = "the offset of the page's first customer", required = false) @RequestParam(value = "offset", required = false, defaultValue = "0") Integer offset) {
		logger.debug("Fetching a page of customers (offset={},limit={},filter='{}')", offset, limit, filter);
		Page<CustomerAggregateRoot> page = customerService.getCustomers(filter, limit, offset);
		List<CustomerDto> customerDtos = page.getElements().stream()
				.map(CustomerDto::fromDomainObject)
				.collect(Collectors.toList());
		customerDtos.forEach(this::addCustomerLinks);
		PaginatedCustomerResponseDto paginatedResponseDto = new PaginatedCustomerResponseDto(filter, limit, offset, page.getSize(), customerDtos);
		paginatedResponseDto.add(linkTo(methodOn(PolicyCustomerController.class).getCustomers(filter, limit, offset)).withSelfRel());
		if (offset > 0) {
			paginatedResponseDto.add(linkTo(methodOn(PolicyCustomerController.class).getCustomers(filter, limit, Math.max(0, offset - limit))).withRel("prev"));
		}
		if (offset < page.getSize() - limit) {
			paginatedResponseDto.add(linkTo(methodOn(PolicyCustomerController.class).getCustomers(filter, limit, offset + limit)).withRel("next"));
		}
		return ResponseEntity.ok(paginatedResponseDto);
	}

	private void addCustomerLinks(CustomerDto customerDto) {
		CustomerIdDto customerId = new CustomerIdDto(customerDto.getCustomerId());
		Link selfLink = linkTo(methodOn(PolicyCustomerController.class).getCustomer(customerId)).withSelfRel();
		Link policiesLink = linkTo(methodOn(PolicyCustomerController.class).getPolicies(customerId, "")).withRel("policies");
		customerDto.add(selfLink);
		customerDto.add(policiesLink);
	}

	@Operation(summary = "Get customer with a given customer id.")
	@GetMapping(value = "/{customerIdDto}")
	public ResponseEntity<CustomerDto> getCustomer(
			@Parameter(description = "the customer's unique id", required = true) @PathVariable CustomerIdDto customerIdDto) {
		CustomerId customerId = new CustomerId(customerIdDto.getId());
		logger.debug("Fetching a customer with id '{}'", customerId.getId());
		List<CustomerAggregateRoot> customers = customerService.getCustomers(customerId.getId());
		if (customers.isEmpty()) {
			final String errorMessage = "Failed to find a customer with id '{}'";
			logger.warn(errorMessage, customerId.getId());
			throw new CustomerNotFoundException(errorMessage);
		}

		CustomerDto customer = CustomerDto.fromDomainObject(customers.get(0));
		addCustomerLinks(customer);
		return ResponseEntity.ok(customer);
	}

	@Operation(summary = "Get a customer's policies.")
	@GetMapping(value = "/{customerIdDto}/policies")
	public ResponseEntity<List<PolicyDto>> getPolicies(
			@Parameter(description = "the customer's unique id", required = true) @PathVariable CustomerIdDto customerIdDto,
			@Parameter(description = "a comma-separated list of the fields that should be expanded in the response", required = false) @RequestParam(value = "expand", required = false, defaultValue = "") String expand) {
		CustomerId customerId = new CustomerId(customerIdDto.getId());
		logger.debug("Fetching policies for customer with id '{}' (fields='{}')", customerId.getId(), expand);
		List<PolicyAggregateRoot> policies = policyRepository.findAllByCustomerIdOrderByCreationDateDesc(customerId);
		List<PolicyDto> policyDtos = policies.stream().map(p -> {
			PolicyDto policyDto = PolicyDto.fromDomainObject(p);
			if (expand.equals("customer")) {
				List<CustomerAggregateRoot> cs = customerService.getCustomers(p.getCustomerId().getId());
				if (!cs.isEmpty()) {
					policyDto.setCustomer(CustomerDto.fromDomainObject(cs.get(0)));
				}
			}
			Link selfLink = linkTo(methodOn(PolicyController.class).getPolicy(p.getId(), expand)).withSelfRel();
			policyDto.add(selfLink);
			return policyDto;
		}).collect(Collectors.toList());
		return ResponseEntity.ok(policyDtos);
	}
}
