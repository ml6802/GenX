import re
import csv

def parse_iteration_data(filename):
    """Parse iteration data from test_output_parsing.txt"""
    k_values = []
    LB_values = []
    UB_values = []
    gap_values = []
    cpu_time_values = []
    
    # Set to keep track of already processed k values (to handle duplicates)
    processed_k = set()
    
    # Read the file line by line
    with open(filename, 'r') as file:
        for line in file:
            # Check if line starts with "k = "
            if line.startswith("k = "):
                try:
                    # Use regex to extract the numeric values
                    k_match = re.search(r'k = (\d+)', line)
                    lb_match = re.search(r'LB = ([\d\.e\+\-]+)', line)
                    ub_match = re.search(r'UB = ([\d\.e\+\-]+)', line)
                    gap_match = re.search(r'Gap = ([\d\.e\+\-]+)', line)
                    cpu_match = re.search(r'CPU Time = ([\d\.e\+\-]+)', line)
                    
                    if all([k_match, lb_match, ub_match, gap_match, cpu_match]):
                        k_val = int(k_match.group(1))
                        
                        # Skip if we've already processed this k value
                        if k_val in processed_k:
                            continue
                        
                        lb_val = float(lb_match.group(1))
                        ub_val = float(ub_match.group(1))
                        gap_val = float(gap_match.group(1))
                        cpu_val = float(cpu_match.group(1))
                        
                        # Store the values
                        k_values.append(k_val)
                        LB_values.append(lb_val)
                        UB_values.append(ub_val)
                        gap_values.append(gap_val)
                        cpu_time_values.append(cpu_val)
                        
                        # Mark this k value as processed
                        processed_k.add(k_val)
                        
                except Exception as e:
                    print(f"Warning: Could not parse line: {line.strip()}")
                    print(f"Error: {e}")
    
    # Sort by k values to ensure proper order
    combined = list(zip(k_values, LB_values, UB_values, gap_values, cpu_time_values))
    combined.sort(key=lambda x: x[0])
    
    if combined:
        k_values, LB_values, UB_values, gap_values, cpu_time_values = zip(*combined)
        return {
            'k': list(k_values),
            'LB': list(LB_values),
            'UB': list(UB_values),
            'gap': list(gap_values),
            'cpu_time': list(cpu_time_values)
        }
    else:
        return {'k': [], 'LB': [], 'UB': [], 'gap': [], 'cpu_time': []}

def main():
    # Parse the data
    print("Parsing iteration data from test_output_parsing.txt...")
    data = parse_iteration_data("test_output_parsing.txt")
    
    if not data['k']:
        print("No data found!")
        return
    
    # Display the results
    print("\nParsed Data:")
    print("=" * 50)
    print(f"Number of iterations: {len(data['k'])}")
    print()
    
    print("Iteration vectors:")
    print(f"k = {data['k']}")
    print()
    print(f"LB = {data['LB']}")
    print()
    print(f"UB = {data['UB']}")
    print()
    print(f"Gap = {data['gap']}")
    print()
    print(f"CPU Time = {data['cpu_time']}")
    
    # Print summary statistics
    print("\nSummary Statistics:")
    print("=" * 30)
    print(f"Iterations: {min(data['k'])} to {max(data['k'])}")
    print(f"Final Lower Bound: {data['LB'][-1]:e}")
    print(f"Final Upper Bound: {data['UB'][-1]:e}")
    print(f"Final Gap: {data['gap'][-1]:.2f}%")
    print(f"Total CPU Time: {data['cpu_time'][-1]:.2f} seconds")
    print(f"Total CPU Time: {data['cpu_time'][-1]/3600:.2f} hours")
    
    # Save to CSV file
    print("\nSaving data to iterations_data.csv...")
    with open("iterations_data.csv", 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(['iteration', 'lower_bound', 'upper_bound', 'gap', 'cpu_time'])
        for i in range(len(data['k'])):
            writer.writerow([data['k'][i], data['LB'][i], data['UB'][i], data['gap'][i], data['cpu_time'][i]])
    print("Data saved to iterations_data.csv")

if __name__ == "__main__":
    main()