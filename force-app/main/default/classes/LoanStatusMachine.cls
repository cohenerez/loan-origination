
public inherited sharing class LoanStatusMachine {

    public static final String DRAFT            = 'Draft';
    public static final String SUBMITTED        = 'Submitted';
    public static final String SCORING          = 'Scoring';
    public static final String PENDING_APPROVAL = 'Pending_Approval';
    public static final String APPROVED         = 'Approved';
    public static final String REJECTED         = 'Rejected';
    public static final String FUNDED           = 'Funded';

    /** Statuses a new application may be created in (Submitted allows external upserts). */
    public static final Set<String> INITIAL_STATES = new Set<String>{ DRAFT, SUBMITTED };

    /** Statuses in which the loan details (amount, term, income, purpose, applicant) may be edited. */
    public static final Set<String> EDITABLE_STATES = new Set<String>{ DRAFT, SUBMITTED };

    /** Statuses that represent a credit decision. */
    public static final Set<String> DECISION_STATES = new Set<String>{ APPROVED, REJECTED };

    private static final Map<String, Set<String>> TRANSITIONS = new Map<String, Set<String>>{
        DRAFT            => new Set<String>{ SUBMITTED },
        SUBMITTED        => new Set<String>{ SCORING, DRAFT },
        // Scoring can fall back to Submitted when the scoring service fails, so it can be retried
        SCORING          => new Set<String>{ PENDING_APPROVAL, REJECTED, SUBMITTED },
        // Pending_Approval can be returned for changes, e.g. when the customer asks for a different amount
        PENDING_APPROVAL => new Set<String>{ APPROVED, REJECTED, SUBMITTED },
        APPROVED         => new Set<String>{ FUNDED },
        REJECTED         => new Set<String>(),
        FUNDED           => new Set<String>()
    };

    public static Boolean canTransition(String fromStatus, String toStatus) {
        if (fromStatus == toStatus) {
            return true;
        }
        Set<String> allowed = TRANSITIONS.get(fromStatus);
        return allowed != null && allowed.contains(toStatus);
    }

    public static Set<String> allowedFrom(String fromStatus) {
        Set<String> allowed = TRANSITIONS.get(fromStatus);
        return allowed == null ? new Set<String>() : allowed.clone();
    }
}
