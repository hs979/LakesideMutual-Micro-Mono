package com.lakesidemutual.interfaces.configuration;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SwaggerConfiguration {
	@Bean
	public OpenAPI lakesideMutualApi() {
		return new OpenAPI()
				.info(new Info().title("Lakeside Mutual Monolith API")
						.description("Unified API combining Customer Core, Customer Management, Customer Self-Service, and Policy Management.")
						.version("v1.0.0")
						.license(new License().name("Apache 2.0")));
	}
}
