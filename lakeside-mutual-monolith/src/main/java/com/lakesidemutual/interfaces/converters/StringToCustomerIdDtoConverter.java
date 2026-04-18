package com.lakesidemutual.interfaces.converters;

import org.springframework.core.convert.converter.Converter;
import org.springframework.stereotype.Component;

import com.lakesidemutual.interfaces.dtos.policy.customer.CustomerIdDto;

/**
 * This converter class allows us to use CustomerIdDto as the type of
 * a @PathVariable parameter in a Spring @RestController class.
 */
@Component
public class StringToCustomerIdDtoConverter implements Converter<String, CustomerIdDto> {
	@Override
	public CustomerIdDto convert(String source) {
		CustomerIdDto customerId = new CustomerIdDto();
		customerId.setId(source);
		return customerId;
	}
}

