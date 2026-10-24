import lambda_function

def test_lambda_response_structure():
    # mock event
    test_event = {}
    test_context = {}
    
    # chacking if the lambda_handler function exists
    assert hasattr(lambda_function, 'lambda_handler')