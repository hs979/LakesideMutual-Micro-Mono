package com.lakesidemutual.interfaces.management;

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
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.lakesidemutual.application.CustomerService;
import com.lakesidemutual.application.Page;
import com.lakesidemutual.domain.customer.Address;
import com.lakesidemutual.domain.customer.CustomerAggregateRoot;
import com.lakesidemutual.domain.customer.CustomerId;
import com.lakesidemutual.domain.customer.CustomerProfileEntity;
import com.lakesidemutual.interfaces.dtos.management.CustomerDto;
import com.lakesidemutual.interfaces.dtos.management.CustomerNotFoundException;
import com.lakesidemutual.interfaces.dtos.management.CustomerProfileDto;
import com.lakesidemutual.interfaces.dtos.management.PaginatedCustomerResponseDto;

@RestController
@RequestMapping("/api/management/customers")
public class ManagementCustomerController {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private CustomerService customerService;

	@Operation(summary = "Get all customers.")
	@GetMapping
	public ResponseEntity<PaginatedCustomerResponseDto> getCustomers(
			@Parameter(description = "search terms to filter the customers by name", required = false) @RequestParam(value = "filter", required = false, defaultValue = "") String filter,
			@Parameter(description = "the maximum number of customers per page", required = false) @RequestParam(value = "limit", required = false, defaultValue = "10") Integer limit,
			@Parameter(description = "the offset of the page's first customer", required = false) @RequestParam(value = "offset", required = false, defaultValue = "0") Integer offset) {
		Page<CustomerAggregateRoot> page = customerService.getCustomers(filter, limit, offset);
		List<CustomerDto> customerDtos = page.getElements().stream()
				.map(CustomerDto::fromDomainObject)
				.collect(Collectors.toList());
		PaginatedCustomerResponseDto response = new PaginatedCustomerResponseDto(filter, limit, offset, page.getSize(), customerDtos);
		return ResponseEntity.ok(response);
	}

	@Operation(summary = "Get customer with a given customer id.")
	@GetMapping(value = "/{customerId}")
	public ResponseEntity<CustomerDto> getCustomer(
			@Parameter(description = "the customer's unique id", required = true) @PathVariable CustomerId customerId) {
		List<CustomerAggregateRoot> customers = customerService.getCustomers(customerId.getId());
		if (customers.isEmpty()) {
			final String errorMessage = "Failed to find a customer with id '" + customerId.getId() + "'.";
			logger.info(errorMessage);
			throw new CustomerNotFoundException(errorMessage);
		}
		return ResponseEntity.ok(CustomerDto.fromDomainObject(customers.get(0)));
	}

	@Operation(summary = "Update the profile of the customer with the given customer id")
	@PutMapping(value = "/{customerId}")
	public ResponseEntity<CustomerDto> updateCustomer(
			@Parameter(description = "the customer's unique id", required = true) @PathVariable CustomerId customerId,
			@Parameter(description = "the customer's updated profile", required = true) @Valid @RequestBody CustomerProfileDto customerProfile) {
		com.lakesidemutual.interfaces.dtos.management.AddressDto addrDto = customerProfile.getCurrentAddress();
		Address address = addrDto != null ? new Address(addrDto.getStreetAddress(), addrDto.getPostalCode(), addrDto.getCity()) : null;
		CustomerProfileEntity profileEntity = new CustomerProfileEntity(customerProfile.getFirstname(), customerProfile.getLastname(),
				customerProfile.getBirthday(), address, customerProfile.getEmail(), customerProfile.getPhoneNumber());
		Optional<CustomerAggregateRoot> updated = customerService.updateCustomerProfile(customerId, profileEntity);
		if (updated.isEmpty()) {
			throw new CustomerNotFoundException("Failed to find a customer with id '" + customerId.getId() + "'.");
		}
		return ResponseEntity.ok(CustomerDto.fromDomainObject(updated.get()));
	}
}
