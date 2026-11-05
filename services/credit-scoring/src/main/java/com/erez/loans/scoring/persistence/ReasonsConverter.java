package com.erez.loans.scoring.persistence;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import java.util.Arrays;
import java.util.List;


@Converter
public class ReasonsConverter implements AttributeConverter<List<String>, String> {

    private static final String SEPARATOR = "\n";

    @Override
    public String convertToDatabaseColumn(List<String> reasons) {
        return reasons == null ? "" : String.join(SEPARATOR, reasons);
    }

    @Override
    public List<String> convertToEntityAttribute(String column) {
        return column == null || column.isBlank() ? List.of() : Arrays.asList(column.split(SEPARATOR));
    }
}
