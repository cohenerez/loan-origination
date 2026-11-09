package com.erez.loans.notifications.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface NotificationRepository extends JpaRepository<Notification, UUID> {

    Optional<Notification> findByEventUuid(String eventUuid);

    List<Notification> findByLoanIdOrderByCreatedAtDesc(String loanId);

    List<Notification> findTop50ByOrderByCreatedAtDesc();
}
