package com.lakesidemutual.interfaces.management;

import java.util.ArrayList;
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
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.lakesidemutual.domain.customer.CustomerId;
import com.lakesidemutual.domain.interactionlog.InteractionLogAggregateRoot;
import com.lakesidemutual.domain.interactionlog.InteractionLogService;
import com.lakesidemutual.infrastructure.InteractionLogRepository;
import com.lakesidemutual.interfaces.dtos.management.InteractionAcknowledgementDto;
import com.lakesidemutual.interfaces.dtos.management.InteractionLogNotFoundException;
import com.lakesidemutual.interfaces.dtos.management.NotificationDto;

/**
 * This REST controller gives clients access to a customer's interaction log. It is an example of the
 * <i>Information Holder Resource</i> pattern. This particular one is a special type of information holder called <i>Master Data Holder</i>.
 *
 * @see <a href="https://www.microservice-api-patterns.org/patterns/responsibility/endpointRoles/InformationHolderResource">Information Holder Resource</a>
 * @see <a href="https://www.microservice-api-patterns.org/patterns/responsibility/informationHolderEndpointTypes/MasterDataHolder">Master Data Holder</a>
 */
@RestController
@RequestMapping("/api/management/interaction-logs")
public class InteractionLogController {
	private final Logger logger = LoggerFactory.getLogger(this.getClass());

	@Autowired
	private InteractionLogService interactionLogService;

	@Autowired
	private InteractionLogRepository interactionLogRepository;

	@Autowired
	private SimpMessagingTemplate simpMessagingTemplate;

	@Operation(summary = "Get the interaction log for a customer with a given customer id.")
	@GetMapping(value = "/{customerId}")
	public ResponseEntity<InteractionLogAggregateRoot> getInteractionLog(
			@Parameter(description = "the customer's unique id", required = true) @PathVariable CustomerId customerId) {
		final String customerIdStr = customerId.getId();
		Optional<InteractionLogAggregateRoot> optInteractionLog = interactionLogRepository.findById(customerIdStr);
		if (!optInteractionLog.isPresent()) {
			logger.info("Failed to find an interaction log for the customer with id '" + customerId.toString() + "'. Returning an empty interaction log instead.");
			final InteractionLogAggregateRoot emptyInteractionLog = new InteractionLogAggregateRoot(customerIdStr, "", null, new ArrayList<>());
			return ResponseEntity.ok(emptyInteractionLog);
		}

		final InteractionLogAggregateRoot interactionLog = optInteractionLog.get();
		return ResponseEntity.ok(interactionLog);
	}

	@Operation(summary = "Acknowledge all of a given customer's interactions up to the given interaction id.")
	@PatchMapping(value = "/{customerId}")
	public ResponseEntity<InteractionLogAggregateRoot> acknowledgeInteractions(
			@Parameter(description = "the customer's unique id", required = true) @PathVariable CustomerId customerId,
			@Parameter(description = "the id of the newest acknowledged interaction", required = true) @Valid @RequestBody InteractionAcknowledgementDto interactionAcknowledgementDto) {
		final String customerIdStr = customerId.getId();
		Optional<InteractionLogAggregateRoot> optInteractionLog = interactionLogRepository.findById(customerIdStr);
		if (!optInteractionLog.isPresent()) {
			final String errorMessage = "Failed to acknowledge interactions, because there is no interaction log for customer with id '" + customerId.getId() + "'.";
			logger.info(errorMessage);
			throw new InteractionLogNotFoundException(errorMessage);
		}

		final InteractionLogAggregateRoot interactionLog = optInteractionLog.get();
		interactionLog.setLastAcknowledgedInteractionId(interactionAcknowledgementDto.getLastAcknowledgedInteractionId());
		interactionLogRepository.save(interactionLog);
		broadcastNotifications();
		return ResponseEntity.ok(interactionLog);
	}

	private void broadcastNotifications() {
		logger.info("Broadcasting updated notifications");
		final List<NotificationDto> notifications = interactionLogService.getNotifications().stream()
				.map(notification -> new NotificationDto(notification.getCustomerId(), notification.getUsername(), notification.getCount()))
				.collect(Collectors.toList());
		simpMessagingTemplate.convertAndSend("/topic/notifications", notifications);
	}
}
