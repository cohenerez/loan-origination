package com.erez.loans.notifications.api;

import com.erez.loans.notifications.domain.NotificationRepository;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;


@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {

    private final NotificationRepository repository;

    public NotificationController(NotificationRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    public List<NotificationView> list(@RequestParam(required = false) String loanId) {
        var notifications = loanId == null
                ? repository.findTop50ByOrderByCreatedAtDesc()
                : repository.findByLoanIdOrderByCreatedAtDesc(loanId);
        return notifications.stream().map(NotificationView::of).toList();
    }
}
