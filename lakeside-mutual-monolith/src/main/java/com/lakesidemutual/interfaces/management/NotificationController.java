package com.lakesidemutual.interfaces.management;

import java.util.List;
import java.util.stream.Collectors;

import io.swagger.v3.oas.annotations.Operation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.lakesidemutual.domain.interactionlog.InteractionLogService;
import com.lakesidemutual.interfaces.dtos.management.NotificationDto;

/**
 * This REST controller gives clients access the current list of unacknowledged chat notifications. It is an example of the
 * <i>Information Holder Resource</i> pattern. This particular one is a special type of information holder called <i>Master Data Holder</i>.
 *
 * @see <a href="https://www.microservice-api-patterns.org/patterns/responsibility/endpointRoles/InformationHolderResource">Information Holder Resource</a>
 * @see <a href="https://www.microservice-api-patterns.org/patterns/responsibility/informationHolderEndpointTypes/MasterDataHolder">Master Data Holder</a>
 */
@RestController
@RequestMapping("/api/management/notifications")
public class NotificationController {
	@Autowired
	private InteractionLogService interactionLogService;

	@Operation(summary = "Get a list of all unacknowledged notifications.")
	@GetMapping
	public ResponseEntity<List<NotificationDto>> getNotifications() {
		final List<NotificationDto> notifications = interactionLogService.getNotifications().stream()
				.map(notification -> new NotificationDto(notification.getCustomerId(), notification.getUsername(), notification.getCount()))
				.collect(Collectors.toList());
		return ResponseEntity.ok(notifications);
	}
}
