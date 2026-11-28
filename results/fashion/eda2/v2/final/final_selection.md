# EDA2 final selection

## Cấu hình đã chốt để sử dụng

**B0 / K=32 / seed=123 / S0** (`B0_K32_seed123_S0`) là cấu hình người dùng chọn để biểu diễn ảnh thành transaction. S0 lưu tập visual word xuất hiện trong mỗi ảnh.

Dùng bộ [transactions.jsonl](../../../../../results/fashion/tc/tc6_configs/S0/FashionMNIST_T2_S0_B0_K32_seed123/transactions.jsonl) hiện có với **70.000 transaction**, **0 transaction rỗng** và kiểm định **PASS**. SHA-256 khớp manifest EDA2 (`b078e485064bfdacea4b5faa5f027efe7123af32a2db2c27acf415d6b1dd7d70`).

Kết luận theo rubric EDA2 vẫn là `INCONCLUSIVE` vì phần D chưa có đánh giá trực quan và độ dư thừa của mẫu.

## Trạng thái theo rubric EDA2

**Status: INCONCLUSIVE.** This status remains until the required EDA2 evidence and human review are complete.

The notebook does not select a configuration from distortion, raw itemset count, or class-label similarity alone. Review `pilot_eclat/shortlist_decision.csv`, C3 results and interpretability evidence before recording a final choice.

Source transaction databases and codebooks remain read-only.
