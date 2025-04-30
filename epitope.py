from playwright.sync_api import sync_playwright
from urllib.parse import urljoin
import json, time
import re


def extract_table_data(base_url, target):

    with sync_playwright() as p:
        target_url = f"{base_url}{target}"
        print(target_url)
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(target_url)

        try:
            # 1. Wait for the main table to load
            page.wait_for_selector("table.table-bordered tbody tr", timeout=10000)
            table = page.query_selector("table.table-bordered")
            table_rows = table.query_selector_all("tbody tr")
            data = []
            for row in table_rows:
                row_data = {}
                cells = row.query_selector_all("td")

                # 2 Extract main data
                try:
                    row_data["ID"] = cells[0].inner_text().strip()
                    row_data["Name"] = cells[1].inner_text().strip()
                    row_data["Description"] = cells[2].inner_text().strip()
                    row_data["Evidence"] = cells[3].inner_text().strip()
                    row_data["Exposition"] = cells[4].inner_text().strip()
                    row_data["Status"] = cells[5].inner_text().strip()
                    row_data["Eplet Structure"] = cells[6].inner_text().strip()
                    row_data["Frequency"] = cells[7].inner_text().strip()

                except IndexError:
                    print("skipping")
                    continue

                # 3. Extract Alleles from "HLA alleles that share the eplet..." Link
                view_link = cells[9].query_selector(
                    'a[data-controller="modal"][data-action="click->modal#loadAndShow"][data-modal-url-value*="/all_alleles"]'
                )
                if view_link:
                    try:
                        # Click the link to trigger the pop-up
                        view_link.click()

                        # Wait for *any* modal to load
                        page.wait_for_selector(
                            'div[id^="all_alleles_modal"]', timeout=10000
                        )

                        # Extract Allele Data from the Pop-up (Find the correct modal)
                        modal_div = page.query_selector('div[id^="all_alleles_modal"]')
                        if modal_div:
                            allele_container = modal_div.query_selector(".modal-body p")
                            if allele_container:
                                alleles_text = allele_container.inner_text().strip()
                                # Split the text by commas, but handle potential extra whitespace
                                row_data["Alleles"] = [
                                    allele.strip() for allele in alleles_text.split(",")
                                ]
                                print(
                                    "success - alleles extracted for ID:",
                                    row_data["ID"],
                                    "database:",
                                    target,
                                )
                            else:
                                row_data["Alleles"] = None
                        else:
                            row_data["Alleles"] = None

                        # Close the pop-up (Find the correct close button)
                        close_button = modal_div.query_selector("button.btn")
                        if close_button:
                            close_button.click()

                    except Exception as e:
                        print(f"Error processing popup: {e}")
                        row_data["Alleles"] = None
                else:
                    row_data["Alleles"] = None

                data.append(row_data)

            browser.close()
            return data

        except Exception as e:
            print(f"Error during table extraction: {e}")
            browser.close()
            return None
