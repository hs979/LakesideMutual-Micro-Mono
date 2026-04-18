package com.lakesidemutual.interfaces.dtos.policy.insurancequoterequest;

import java.util.Date;

import com.lakesidemutual.domain.policy.InsuranceOptionsEntity;
import com.lakesidemutual.domain.policy.InsuranceType;
import com.lakesidemutual.interfaces.dtos.policy.policy.MoneyAmountDto;

/**
 * InsuranceOptionsDto is a data transfer object (DTO) that contains the insurance options
 * (e.g., start date, insurance type, etc.) that a customer selected for an Insurance Quote Request.
 */
public class InsuranceOptionsDto {
	private Date startDate;
	private String insuranceType;
	private MoneyAmountDto deductible;

	public InsuranceOptionsDto() {
	}

	private InsuranceOptionsDto(Date startDate, String insuranceType, MoneyAmountDto deductible) {
		this.startDate = startDate;
		this.insuranceType = insuranceType;
		this.deductible = deductible;
	}

	public static InsuranceOptionsDto fromDomainObject(InsuranceOptionsEntity insuranceOptions) {
		Date startDate = insuranceOptions.getStartDate();
		InsuranceType insuranceType = insuranceOptions.getInsuranceType();
		String insuranceTypeDto = insuranceType.getName();
		MoneyAmountDto deductibleDto = MoneyAmountDto.fromDomainObject(insuranceOptions.getDeductible());
		return new InsuranceOptionsDto(startDate, insuranceTypeDto, deductibleDto);
	}

	public InsuranceOptionsEntity toDomainObject() {
		return new InsuranceOptionsEntity(startDate, new InsuranceType(insuranceType), deductible.toDomainObject());
	}

	public Date getStartDate() {
		return startDate;
	}

	public void setStartDate(Date startDate) {
		this.startDate = startDate;
	}

	public String getInsuranceType() {
		return insuranceType;
	}

	public void setInsuranceType(String insuranceType) {
		this.insuranceType = insuranceType;
	}

	public MoneyAmountDto getDeductible() {
		return deductible;
	}

	public void setDeductible(MoneyAmountDto deductible) {
		this.deductible = deductible;
	}
}
