with cte as (
    SELECT *
    FROM (
        SELECT  ROW_NUMBER() OVER (PARTITION BY PAF.PERSON_NUMBER 
                                ORDER BY AS2.EFFECTIVE_START_DATE DESC) AS RN,
                PAF.PERSON_NUMBER,
                PAF.PERSON_ID,
                AS2.ASSIGNMENT_NUMBER,
                AS2.EFFECTIVE_START_DATE,
                AS2.EFFECTIVE_END_DATE,
                AS2.GRADE_ID,
                AS2.ASSIGNMENT_NAME,
                AS2.ASSIGNMENT_STATUS_TYPE,
                MAX(AS2.EFFECTIVE_END_DATE) OVER (PARTITION BY PAF.PERSON_NUMBER) AS MAX_END_DATE
        FROM    PER_ALL_PEOPLE_F PAF
        JOIN    PER_ALL_ASSIGNMENTS_M AS2
            ON AS2.PERSON_ID = PAF.PERSON_ID
            AND (AS2.ASSIGNMENT_TYPE LIKE 'E%' OR AS2.ASSIGNMENT_TYPE LIKE 'C%')
            AND (AS2.ASSIGNMENT_TYPE NOT LIKE 'ET%' AND AS2.ASSIGNMENT_TYPE NOT LIKE 'CT%')
        WHERE   SYSDATE BETWEEN PAF.EFFECTIVE_START_DATE AND PAF.EFFECTIVE_END_DATE
        AND   (PAF.PERSON_NUMBER LIKE :PERSON_NUMBER OR :PERSON_NUMBER IS NULL)
    )
    WHERE (
            -- Case 1: end_date is null → use sysdate
            (:END_DATE IS NULL AND SYSDATE BETWEEN EFFECTIVE_START_DATE AND EFFECTIVE_END_DATE)

            -- Case 2: end_date within some assignment
        OR (:END_DATE IS NOT NULL AND :END_DATE BETWEEN EFFECTIVE_START_DATE AND EFFECTIVE_END_DATE)

            -- Case 3: end_date beyond everything → take open-ended row (4712)
        OR (:END_DATE IS NOT NULL AND :END_DATE > MAX_END_DATE AND EFFECTIVE_END_DATE = DATE '4712-12-31')
    )   
), INTERMEDIATE_DATA AS (

SELECT      distinct --row_number() over(partition by can.person_id order by sub.submission_date desc) as rn
            REQ.REQUISITION_NUMBER
            ,PAF.PERSON_NUMBER
            ,CAN.CANDIDATE_NUMBER
            ,NAM.FULL_NAME
            ,ASS.ASSIGNMENT_NAME                            AS "Current Assignment"
            ,OFA.ASSIGNMENT_NUMBER                          AS "OFFER_ASSIGNMENT_NUMBER"
            ,GRT.NAME                                       AS "OFFER_GRADE"
            ,GRD.ATTRIBUTE_NUMBER2                          AS "OFFER_GRD_EQUITY"
            ,PEEVF.SCREEN_ENTRY_VALUE                       AS "Comp_Equity"
            ,TO_CHAR(SER.DATE_START, 'YYYY-MM-dd')          AS HIRING_DATE
            ,PAYTL.ELEMENT_NAME
            ,AS2.ASSIGNMENT_NAME                            AS "ASSIGNMENT_TITLE"
            ,AS2.ASSIGNMENT_NUMBER                          AS "ASSIGNMENT_NUMBER"
            ,AS2.EFFECTIVE_START_DATE
            ,AS2.EFFECTIVE_END_DATE
            ,GRT2.NAME                                      AS GRD2_GRADE_NAME
            ,GRD2.ATTRIBUTE_NUMBER2                         AS GRD2_EQUITY
            ,ASS.EFFECTIVE_START_DATE           as "current_assignment_start_date"
            ,ASS.EFFECTIVE_END_DATE             as "current_assignment_end_date"
            ,SUB.submission_date
FROM        IRC_REQUISITIONS_VL         REQ 
INNER JOIN  IRC_SUBMISSIONS             SUB     ON      REQ.REQUISITION_ID              = SUB.REQUISITION_ID
LEFT JOIN   IRC_CANDIDATES              CAN     ON      CAN.PERSON_ID                   = SUB.PERSON_ID
                                                    AND CAN.DELETION_DATE               IS NULL                                                  
LEFT JOIN   PER_PERSON_NAMES_F          NAM     ON      NAM.PERSON_ID                   = CAN.PERSON_ID
                                                    AND SYSDATE                         BETWEEN NAM.effective_start_date AND NAM.effective_end_date
                                                    AND NAME_TYPE                       = 'GLOBAL'  
LEFT JOIN   PER_ALL_PEOPLE_F            PAF     ON      PAF.PERSON_ID                   = CAN.PERSON_ID      
                                                    AND SYSDATE                         BETWEEN PAF.EFFECTIVE_START_DATE AND PAF.EFFECTIVE_END_DATE
LEFT JOIN   PER_ALL_ASSIGNMENTS_M       ASS     ON      ASS.PERSON_ID                   = PAF.PERSON_ID
                                                    AND TRUNC(SYSDATE)                  BETWEEN ASS.EFFECTIVE_START_DATE AND ASS.EFFECTIVE_END_DATE
                                                    AND ASS.EFFECTIVE_LATEST_CHANGE     = 'Y'  
                                                    AND ASS.PRIMARY_FLAG                = 'Y'
                                                    AND ASSIGNMENT_STATUS_TYPE          = 'ACTIVE'
LEFT JOIN   PER_PERIODS_OF_SERVICE      SER     ON      SER.PERIOD_OF_SERVICE_ID        = ASS.PERIOD_OF_SERVICE_ID
INNER JOIN  IRC_OFFERS                  OFR     ON      OFR.SUBMISSION_ID               = SUB.SUBMISSION_ID 
INNER JOIN  PER_ALL_ASSIGNMENTS_M       OFA     ON      OFA.ASSIGNMENT_ID               = OFR.ASSIGNMENT_OFFER_ID
                                                    AND OFA.ASSIGNMENT_TYPE             = 'O'
LEFT JOIN   PER_GRADES_F                GRD     ON      OFA.GRADE_ID                    = GRD.GRADE_ID
                                                    AND SYSDATE                         BETWEEN GRD.EFFECTIVE_START_DATE AND GRD.effective_end_date
LEFT JOIN   PER_GRADES_F_TL             GRT     ON      OFA.GRADE_ID                    = GRT.GRADE_ID
                                                    AND GRT.LANGUAGE                    = 'US'
LEFT JOIN   PAY_ELEMENT_ENTRIES_F       PEEF    ON      PEEF.PERSON_ID                  = CAN.PERSON_ID
LEFT JOIN   PAY_ELEMENT_TYPES_F         PETF    ON      PEEF.ELEMENT_TYPE_ID            = PETF.ELEMENT_TYPE_ID
                                                    AND TRUNC(SYSDATE)                  BETWEEN TRUNC(PETF.EFFECTIVE_START_DATE) AND TRUNC(PETF.EFFECTIVE_END_DATE)
INNER JOIN  PAY_ELEMENT_TYPES_TL        PAYTL   ON      PETF.ELEMENT_TYPE_ID            = PAYTL.ELEMENT_TYPE_ID
                                                    AND PAYTL.language                  = 'US'     
                                                    AND PAYTL.ELEMENT_NAME              IN ('Glaukos Equity Grant', 'Glaukos Stock Grant')
LEFT JOIN   PAY_ELEMENT_ENTRY_VALUES_F  PEEVF   ON      PEEVF.ELEMENT_ENTRY_ID          = PEEF.ELEMENT_ENTRY_ID
                                                    -- AND TRUNC(SYSDATE)                  BETWEEN TRUNC(PEEVF.EFFECTIVE_START_DATE) AND TRUNC(PEEVF.EFFECTIVE_END_DATE)
INNER JOIN  PAY_INPUT_VALUES_F          PIVF    ON      PIVF.INPUT_VALUE_ID             = PEEVF.INPUT_VALUE_ID
                                                    AND TRUNC(SYSDATE)                  BETWEEN TRUNC(PIVF.EFFECTIVE_START_DATE) AND TRUNC(PIVF.EFFECTIVE_END_DATE)
                                                    AND PIVF.BASE_NAME                  IN ('Amount')
LEFT JOIN 	HCM_LOOKUPS 				TTL		ON      TTL.LOOKUP_TYPE                 = 'TITLE'
										   		    AND NAM.TITLE 				        = TTL.LOOKUP_CODE
LEFT JOIN   cte                         AS2     ON      AS2.PERSON_ID                   = PAF.PERSON_ID
LEFT JOIN   PER_GRADES_F                GRD2    ON      AS2.GRADE_ID                    = GRD2.GRADE_ID
                                                    AND SYSDATE                         BETWEEN GRD2.EFFECTIVE_START_DATE AND GRD2.effective_end_date
LEFT JOIN   PER_GRADES_F_TL             GRT2    ON      AS2.GRADE_ID                    = GRT2.GRADE_ID
                                                    AND GRT2.LANGUAGE                    = 'US'

WHERE   1 = 1
    -- AND trunc(ASS.EFFECTIVE_START_DATE) >= trunc(:START_DATE)
    AND trunc(SER.DATE_START) BETWEEN :START_DATE AND nvl(:END_DATE, '4712-12-31')
    AND (PAF.PERSON_NUMBER LIKE :PERSON_NUMBER OR :PERSON_NUMBER IS NULL)
    -- AND PAF.PERSON_NUMBER = '101025'
        -- AND REQ.REQUISITION_NUMBER  LIKE '1614'
--         AND CAN.CANDIDATE_NUMBER    = '4980474'
ORDER BY REQ.REQUISITION_NUMBER,AS2.EFFECTIVE_START_DATE, AS2.EFFECTIVE_END_DATE
), FINAL_DATA AS (

SELECT  row_number() over(partition by CANDIDATE_NUMBER order by submission_date desc) as rn,
        A.*
FROM    INTERMEDIATE_DATA A

)

SELECT * FROM FINAL_DATA
WHERE rn = 1