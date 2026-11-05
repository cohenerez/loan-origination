package com.erez.loans.scoring.engine;

public enum RiskTier {
    A, B, C, D;

    public static RiskTier fromScore(int score) {
        if (score >= 740) return A;
        if (score >= 680) return B;
        if (score >= 620) return C;
        return D;
    }
}
